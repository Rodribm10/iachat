# Cliente HTTP que dispara mensagens do Captain pro webhook do Hermes Agent.
#
# Uso:
#   Captain::Hermes::Client.new(inbox).dispatch(message: msg, conversation: conv)
#
# Resultado: POST autenticado via HMAC-SHA256 (X-Hub-Signature-256) no endpoint
# /webhooks/<subscription_name> do Hermes. O Hermes responde 202 imediato e
# processa em background. Quando terminar, invoca o plugin captain-http-callback
# que POSTa de volta no Captain (HermesCallbackController).
class Captain::Hermes::Client
  TIMEOUT_SECONDS = 10

  # Nomes genéricos que o WhatsApp sugere/preenche sozinho ou que o
  # cliente digita por padrão — nunca são nome de pessoa de verdade.
  GENERIC_FIRST_NAMES = %w[unknown contato cliente whatsapp usuario].freeze

  class DispatchError < StandardError; end

  def initialize(inbox)
    @inbox = inbox
  end

  def dispatch(message:, conversation:, content_override: nil)
    payload = build_payload(message: message, conversation: conversation, content_override: content_override)
    body = payload.to_json
    headers = signed_headers(body)

    Rails.logger.info "[Captain::Hermes::Client] dispatching msg #{message.id} (conv #{conversation.display_id}) → #{webhook_url}"

    response = HTTParty.post(
      webhook_url,
      body: body,
      headers: headers,
      timeout: TIMEOUT_SECONDS
    )

    return response if response.success? || response.code == 202

    raise DispatchError, "Hermes webhook returned HTTP #{response.code}: #{response.body.to_s.truncate(300)}"
  rescue HTTParty::Error, Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED => e
    raise DispatchError, "Network error contacting Hermes (#{e.class}): #{e.message}"
  end

  # Notificação proativa de evento do Captain pro Hermes — usado pra eventos
  # do sistema (Pix pago, reserva expirando, etc) onde o agente deve mandar
  # mensagem espontânea sem o cliente ter falado nada.
  #
  # `system_message` deve começar com `[SISTEMA: <event_type>]` pra Valentina
  # diferenciar de fala real do cliente (ver regra correspondente em SOUL.md).
  def notify_event(conversation:, event_type:, system_message:)
    payload = build_event_payload(conversation, event_type, system_message)
    body = payload.to_json
    headers = signed_headers(body)

    Rails.logger.info "[Captain::Hermes::Client] notifying event #{event_type} (conv #{conversation.display_id}) → #{webhook_url}"

    response = HTTParty.post(webhook_url, body: body, headers: headers, timeout: TIMEOUT_SECONDS)
    return response if response.success? || response.code == 202

    raise DispatchError, "Hermes webhook returned HTTP #{response.code}: #{response.body.to_s.truncate(300)}"
  rescue HTTParty::Error, Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED => e
    raise DispatchError, "Network error contacting Hermes (#{e.class}): #{e.message}"
  end

  private

  attr_reader :inbox

  def webhook_url
    Captain::Hermes.webhook_url_for(inbox)
  end

  def build_payload(message:, conversation:, content_override: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    contact = conversation.contact
    contact_attrs = contact&.custom_attributes.to_h.with_indifferent_access
    cpf_digits = contact_attrs[:cpf].to_s.gsub(/\D/, '')
    history = contact_history_snapshot(contact, conversation)
    reply_context_builder = Captain::Hermes::ReplyContextBuilder.new(message: message, conversation: conversation)
    reply_context = reply_context_builder.perform

    {
      message: reply_context_builder.wrap_message(content_override.presence || text_for_hermes(message)),
      image_urls: image_urls_for_hermes(message),
      reply_context: reply_context,
      contact_name: contact&.name,
      contact_first_name: usable_first_name(contact, conversation),
      contact_id: conversation.contact_id,
      contact_cpf_present: cpf_digits.length == 11,
      contact_email_present: contact&.email.to_s.include?('@'),
      contact_total_reservas: contact_attrs[:total_reservas].to_i,
      contact_ultima_suite: contact_attrs[:ultima_suite].to_s.presence,
      last_reservation_date: history[:last_reservation_date],
      last_reservation_status: history[:last_reservation_status],
      last_reservation_amount: history[:last_reservation_amount],
      last_reservation_suite: history[:last_reservation_suite],
      last_conversation_at: history[:last_conversation_at],
      total_conversations: history[:total_conversations],
      conversation_id: conversation.display_id,
      conversation_internal_id: conversation.id,
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      account_id: inbox.account_id,
      message_id: message.id,
      timestamp: Time.current.to_i
    }
  end

  # Constroi payload pra notificação de evento sistema. Reusa todo o [ctx]
  # do build_payload normal; só substitui `message` pelo system_message e
  # marca `is_system_event=true` pra debug/logging.
  def build_event_payload(conversation, event_type, system_message) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    contact = conversation.contact
    contact_attrs = contact&.custom_attributes.to_h.with_indifferent_access
    cpf_digits = contact_attrs[:cpf].to_s.gsub(/\D/, '')
    history = contact_history_snapshot(contact, conversation)

    {
      message: system_message,
      image_urls: [],
      is_system_event: true,
      event_type: event_type,
      contact_name: contact&.name,
      contact_first_name: usable_first_name(contact, conversation),
      contact_id: conversation.contact_id,
      contact_cpf_present: cpf_digits.length == 11,
      contact_email_present: contact&.email.to_s.include?('@'),
      contact_total_reservas: contact_attrs[:total_reservas].to_i,
      contact_ultima_suite: contact_attrs[:ultima_suite].to_s.presence,
      last_reservation_date: history[:last_reservation_date],
      last_reservation_status: history[:last_reservation_status],
      last_reservation_amount: history[:last_reservation_amount],
      last_reservation_suite: history[:last_reservation_suite],
      last_conversation_at: history[:last_conversation_at],
      total_conversations: history[:total_conversations],
      conversation_id: conversation.display_id,
      conversation_internal_id: conversation.id,
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      account_id: inbox.account_id,
      message_id: 0,
      timestamp: Time.current.to_i
    }
  end

  # Primeiro nome só é "utilizável" quando parece nome de pessoa de
  # verdade. Conservador de propósito: na dúvida, devolve o nome — deixar
  # de chamar alguém pelo nome (falso negativo) é pior que o contrário.
  # Mas tem caso claramente ruim: contato que salva o WhatsApp com o nome
  # do próprio estabelecimento (3 contatos assim na inbox 25 faziam a
  # atendente dizer "Oi, Academia!") ou com emoji/número no lugar do nome
  # ("😅‼️", "556182098580").
  def usable_first_name(contact, conversation)
    full_name = contact&.name.to_s
    first_name = full_name.split.first.to_s
    return nil if first_name.blank? || first_name.length < 2
    return nil if first_name.scan(/\p{L}/).length < 2
    return nil if first_name.match?(/\d/)
    return nil if GENERIC_FIRST_NAMES.include?(normalize_for_comparison(first_name))
    return nil if establishment_name?(full_name, conversation)

    first_name
  end

  # Rejeita quando o contato salvou o WhatsApp com o nome do próprio
  # hotel/academia em vez do nome dele. Compara o nome INTEIRO do contato
  # (não só a primeira palavra) com o nome da inbox e o product_name do
  # assistente, pra um nome tipo "Maurício Informática" não cair só por
  # ter uma palavra em comum com o estabelecimento.
  def establishment_name?(full_name, conversation)
    normalized_contact = normalize_for_comparison(full_name)
    return false if normalized_contact.blank?

    assistant = conversation.inbox.captain_assistant
    [conversation.inbox.name, assistant&.config.to_h['product_name']].any? do |name|
      normalized = normalize_for_comparison(name)
      normalized.present? && (normalized == normalized_contact || normalized.start_with?(normalized_contact))
    end
  end

  def normalize_for_comparison(text)
    ActiveSupport::Inflector.transliterate(text.to_s.downcase).scan(/[a-z0-9]+/).join(' ')
  end

  # Resolve texto da message pro Hermes consumir. Reusa
  # Captain::OpenAiMessageBuilderService que JÁ implementa transcrição de
  # áudio (Whisper) + placeholder pra outros attachments. Garante que
  # mensagem nunca chega vazia mesmo quando cliente manda só áudio/foto.
  # Imagens viram URL/base64 dentro do builder mas pra Hermes via texto, o
  # generate_text_content normaliza pra "[image]" placeholder — ainda
  # útil pro LLM saber que veio anexo visual.
  def text_for_hermes(message)
    raw = message.content.to_s
    return raw if message.attachments.blank?

    Captain::OpenAiMessageBuilderService.new(message: message).generate_text_content.presence || raw
  rescue StandardError => e
    Rails.logger.warn("[Captain::Hermes::Client] text_for_hermes fallback: #{e.class} - #{e.message}")
    message.content.to_s
  end

  # URLs públicas das imagens que vieram nessa message. Plugin captain-webhook
  # do Hermes baixa essas URLs localmente e popula event.media_urls — daí o
  # gpt-5.3-codex (multimodal) consegue ler. Vídeo/PDF/etc ficam de fora por
  # enquanto — só imagem é suportada pro LLM ver de fato.
  def image_urls_for_hermes(message)
    return [] if message.attachments.blank?

    message.attachments.where(file_type: :image).filter_map do |att|
      next nil unless att.file.attached?

      att.download_url.presence || att.external_url.presence || att.file_url
    end
  rescue StandardError => e
    Rails.logger.warn("[Captain::Hermes::Client] image_urls_for_hermes fallback: #{e.class} - #{e.message}")
    []
  end

  # Snapshot eager pra alimentar o [ctx]. Determinístico (lido do DB), só
  # campos estruturados — pra detalhes livres o agente chama
  # `get_contact_history` MCP. Limita a últimas reservation/conversation pra
  # não estourar token budget.
  def contact_history_snapshot(contact, current_conversation)
    return {} if contact.blank?

    last_res = Captain::Reservation
               .where(contact_id: contact.id)
               .where.not(status: 'draft')
               .order(check_in_at: :desc)
               .first
    other_convs = contact.conversations.where.not(id: current_conversation.id)

    {
      last_reservation_date: last_res&.check_in_at&.to_date&.iso8601,
      last_reservation_status: last_res&.status,
      last_reservation_amount: last_res&.total_amount&.to_f,
      last_reservation_suite: last_res&.suite_identifier,
      last_conversation_at: other_convs.maximum(:last_activity_at)&.iso8601,
      total_conversations: other_convs.count
    }.compact
  end

  def signed_headers(body)
    headers = { 'Content-Type' => 'application/json; charset=utf-8' }

    secret = Captain::Hermes.subscription_signing_secret(inbox)
    if secret.present?
      sig = OpenSSL::HMAC.hexdigest('SHA256', secret, body)
      headers['X-Hub-Signature-256'] = "sha256=#{sig}"
    else
      Rails.logger.warn "[Captain::Hermes::Client] no signing secret for inbox #{inbox.id} — Hermes will reject"
    end

    headers
  end
end
