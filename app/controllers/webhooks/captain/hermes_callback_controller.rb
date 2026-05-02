# Recebe o callback do Hermes Agent via plugin captain-http-callback.
#
# Fluxo:
#   1. Captain::Hermes::Client dispara mensagem do cliente pro Hermes
#      (POST /webhooks/captain-inbox-<id> no gateway do Hermes).
#   2. Hermes processa via subscription Codex/etc dele.
#   3. Hermes invoca o plugin captain-http-callback que POSTa nesta URL:
#        POST /webhooks/captain/hermes_callback?inbox_id=<id>
#      Body: { "content": "<resposta>", "reply_to": ..., "metadata": {...}, "timestamp": ... }
#   4. Este controller cria a mensagem outgoing na conversation correta.
#
# Identificação da conversation: como o Hermes não preserva metadata customizado
# de forma confiável, identificamos pela ÚLTIMA conversation pending da inbox
# que recebeu mensagem nos últimos 5 minutos. Aceitável pra PoC com 1 conversa
# de teste por vez. Pra produção, melhorar com Redis: delivery_id → conversation_id.
class Webhooks::Captain::HermesCallbackController < ApplicationController
  RECENT_WINDOW = 5.minutes

  # Placeholders que o LLM emite quando "decide" mandar um sinal de espera
  # antes de chamar uma tool — mas às vezes manda E PARA, sem chamar a tool
  # (api_calls=1 no daemon). Quando detectamos, NÃO entregamos pro cliente
  # e re-disparamos pro Hermes uma instrução pra retomar e chamar a tool.
  PLACEHOLDER_PATTERNS = [
    /\A\s*[⏳⌛]?\s*um\s+momento/i,
    /\A\s*[⏳⌛]\s*vou\s+verificar/i,
    /\A\s*aguarde\s+um\s+instante/i,
    /\A\s*deixa\s+eu\s+(verificar|conferir|checar)/i
  ].freeze
  MAX_PLACEHOLDER_RETRIES = 2

  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_signature
  before_action :fetch_inbox

  def process_payload
    content = extract_content
    return head :bad_request if content.blank?

    conversation = recent_conversation_for(@inbox)
    return log_no_conversation_and_ack if conversation.blank?

    if placeholder_response?(content)
      handle_placeholder_response(conversation, content)
      return head :ok
    end

    log_reply(conversation, content)
    if defined?(Captain::Hermes::DelayedReplyJob)
      Captain::Hermes::DelayedReplyJob.perform_later(conversation.id, content)
    else
      create_outgoing_message(conversation, content)
    end
    head :ok
  rescue StandardError => e
    Rails.logger.error "[Hermes::Callback] error: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    head :internal_server_error
  end

  private

  def placeholder_response?(content)
    return false if content.blank?

    PLACEHOLDER_PATTERNS.any? { |re| content.match?(re) }
  end

  # Quando o Hermes responde só placeholder e para, fazemos 2 coisas:
  #   1. NÃO entregamos a msg pro cliente (UX terrível ver "vou verificar" e
  #      ficar esperando indefinidamente);
  #   2. Disparamos notify_event pro Hermes com instrução pra retomar e
  #      chamar a tool relevante. Limite 2 retries por conversation pra
  #      evitar loop. Após esgotar, marcamos pix_falhou_fallback pra
  #      triagem humana.
  def handle_placeholder_response(conversation, content)
    cache_key = "hermes_placeholder_retry:#{conversation.id}"
    retries = Rails.cache.read(cache_key).to_i

    Rails.logger.warn(
      "[Hermes::Callback] placeholder detectado em conv #{conversation.display_id} (retries=#{retries}): #{content.truncate(80)}"
    )

    if retries >= MAX_PLACEHOLDER_RETRIES
      Rails.logger.error("[Hermes::Callback] esgotou retries de placeholder em conv #{conversation.display_id} — marcando triagem")
      mark_for_human_triage(conversation)
      Rails.cache.delete(cache_key)
      return
    end

    Rails.cache.write(cache_key, retries + 1, expires_in: 5.minutes)
    retrigger_hermes_no_placeholder!(conversation)
  end

  def retrigger_hermes_no_placeholder!(conversation)
    Captain::Hermes::Client.new(@inbox).notify_event(
      conversation: conversation,
      event_type: 'force_tool_call',
      system_message: '[SISTEMA: force_tool_call] Você acabou de emitir um placeholder ' \
                      '("Um momento", "vou verificar" etc) sem chamar tool. Cliente NÃO ' \
                      'recebeu essa mensagem. Releia a última mensagem do cliente e ' \
                      'CHAME A TOOL CORRESPONDENTE AGORA (generate_pix se confirmou ' \
                      'reserva, send_suite_images se pediu foto, faq_lookup se pediu ' \
                      'info de regra). Se faltar dado, pergunte direto sem placeholder.'
    )
  rescue Captain::Hermes::Client::DispatchError => e
    Rails.logger.error("[Hermes::Callback] retrigger falhou: #{e.message}")
    mark_for_human_triage(conversation)
  end

  def mark_for_human_triage(conversation)
    current = conversation.label_list
    conversation.update_labels((current + %w[hermes_placeholder triagem_humana]).uniq)
  end

  def fetch_inbox
    inbox_id = params[:inbox_id].presence || params.dig(:metadata, :inbox_id).presence
    if inbox_id.present?
      @inbox = Inbox.find_by(id: inbox_id)
    elsif (slug = params[:slug].presence)
      # Resolve via slug (hermes_profile_name) — admin pode re-apontar a
      # inbox pra qualquer agente Hermes sem mexer em URL de callback.
      asst = Captain::Assistant.find_by(hermes_profile_name: slug, engine: 'hermes')
      ci = asst&.captain_inboxes&.first
      @inbox = ci&.inbox
    end
    head :not_found if @inbox.blank?
  end

  def verify_signature
    secret = Captain::Hermes.callback_signing_secret
    return true if secret.blank? # validação desabilitada (PoC sem secret)

    signature = request.headers['X-Hermes-Callback-Signature'].to_s
    return head :unauthorized if signature.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)

    true
  end

  def recent_conversation_for(inbox)
    inbox.conversations
         .where('updated_at >= ?', RECENT_WINDOW.ago)
         .where(status: %w[pending open])
         .order(updated_at: :desc)
         .first
  end

  def log_no_conversation_and_ack
    Rails.logger.warn "[Hermes::Callback] no recent conversation for inbox #{@inbox.id} — ignorando callback"
    head :ok
  end

  def extract_content
    normalize_for_whatsapp(params[:content].to_s.strip)
  end

  # Converte markdown padrão (que LLMs default usam) pra formato WhatsApp:
  #   **negrito** -> *negrito*
  # WhatsApp usa single asterisk pra bold; double asterisk aparece literal
  # pro cliente, parecendo bug. Defesa caso o SOUL.md não convença o LLM.
  def normalize_for_whatsapp(content)
    return content if content.blank?

    content.gsub(/\*\*([^*\n]+?)\*\*/, '*\1*')
  end

  def log_reply(conversation, content)
    Rails.logger.info(
      "[Hermes::Callback] reply received for conv #{conversation.display_id} (#{content.length} chars)"
    )
  end

  def create_outgoing_message(conversation, content)
    assistant = conversation.inbox.captain_assistant
    sender = assistant.presence || User.find_by(id: conversation.assignee_id)

    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: sender,
      content: content,
      content_attributes: {
        external_source: 'hermes_callback'
      }
    )
  end
end
