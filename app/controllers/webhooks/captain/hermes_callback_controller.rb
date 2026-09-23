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
# rubocop:disable Metrics/ClassLength
class Webhooks::Captain::HermesCallbackController < ApplicationController
  RECENT_WINDOW = 5.minutes

  # "Um momento — vou verificar" é a frase-âncora de handoff intencional
  # (quando o agente não sabe responder e quer escalar pra humano). NÃO
  # bloqueamos — entregamos pro cliente e marcamos triagem_humana pra
  # próximas msgs não dispararem Hermes.
  HANDOFF_PATTERNS = [
    /\A\s*[⏳⌛]?\s*um\s+momento.*verificar/i,
    /\A\s*[⏳⌛]?\s*um\s+instante.*verificar/i,
    /\A\s*aguarde\s+um\s+instante/i
  ].freeze

  # Loop detection: 2 sinais.
  # 1. Jaccard de tokens >= 0.90 → resposta praticamente idêntica.
  # 2. A mesma PERGUNTA reformulada. Comparar o texto inteiro fazia uma
  #    continuação legítima sobre o mesmo catálogo (Stilo, Alexa, Hidromassagem)
  #    parecer uma repetição.
  # 0.50 era agressivo demais para hotelaria: respostas corretas sobre a mesma
  # reserva reutilizam categoria, data, duração, preço e CTA. Isso marcou como
  # loop avanços reais como "trocar para Luxo" e "mudar para 2 horas".
  LOOP_SIMILARITY_THRESHOLD = 0.90
  LOOP_QUESTION_SIMILARITY = 0.55
  # Uma confirmação curta não escolhe uma das opções que a atendente acabou de
  # oferecer. Nesse caso, uma única pergunta de esclarecimento é legítima;
  # transferir já na primeira tentativa faz a conversa morrer antes de o
  # cliente conseguir responder "valores", "localização" ou "reserva".
  # A segunda repetição semelhante continua sendo loop real e vai para humano.
  AMBIGUOUS_ACKNOWLEDGEMENT_REGEX = /
    \A\s*
    (?:isso(?:\s+mesmo)?|sim|s|ok(?:ay)?|claro|pode(?:\s+ser)?|quero|por\s+favor|pfv|ta|opa|oi|ola|eai|e\s+ai)
    \s*[!?.…]*\z
  /ix
  # Quando o Hermes falha (token expirado, provider fora do ar), ele às vezes
  # devolve o PRÓPRIO erro técnico no lugar da resposta. Sem esta trava isso vai
  # para o cliente: em 25/07/2026 clientes do Instagram receberam — e leram —
  # mensagens como "HTTP 401: Provided authentication token is expired" e
  # "❌ Non-retryable error". Erro técnico nunca é resposta: vira nota privada
  # e triagem humana, para uma pessoa assumir a conversa.
  ERROR_PAYLOAD_PATTERNS = [
    /\bHTTP\s+[45]\d{2}\b/i,
    /authentication\s+failed/i,
    /non-retryable\s+error/i,
    /token\s+(is\s+)?expired/i,
    /switching\s+to\s+fallback\s+provider/i,
    /\bTraceback\b/i,
    /\b(StandardError|NameError|TypeError|NoMethodError|Errno::)\b/
  ].freeze

  # O gateway Hermes usa estas mensagens como confirmação interna quando uma
  # segunda entrada redireciona, enfileira ou interrompe um turno em andamento.
  # Em canais de atendimento elas não são resposta para o cliente e nunca
  # podem atravessar a fronteira do Chatwoot.
  INTERNAL_STATUS_PATTERNS = [
    /\A\s*[↪⏩⚡⏳]?\s*redirected\s+current\s+run\b/i,
    /\A\s*[↪⏩⚡⏳]?\s*steered\s+into\s+current\s+run\b/i,
    /\A\s*[↪⏩⚡⏳]?\s*queued\s+for\s+the\s+next\s+turn\b/i,
    /\A\s*[↪⏩⚡⏳]?\s*interrupting\s+current\s+task\b/i,
    /\A\s*[↪⏩⚡⏳]?\s*subagent\s+working\b/i,
    /\A\s*[↪⏩⚡⏳]?\s*compressing\s+context\b/i
  ].freeze

  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_signature
  before_action :fetch_inbox

  def process_payload
    content = extract_content
    return head :bad_request if content.blank?

    conversation = conversation_from_callback(@inbox) || recent_conversation_for(@inbox)
    return log_no_conversation_and_ack if conversation.blank?

    log_reply(conversation, content)
    return if enforce_known_fact(conversation)
    return if handle_blocked_content(conversation, content)

    return head :ok if detect_handoff_or_loop(conversation, content)

    deliver_outgoing(conversation, content)
    head :ok
  rescue StandardError => e
    Rails.logger.error "[Hermes::Callback] error: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    head :internal_server_error
  end

  private

  def enforce_known_fact(conversation)
    incoming = conversation.messages.where(message_type: :incoming).reorder(created_at: :desc).first
    return false if incoming.blank?

    known_fact = Captain::Hermes::KnownFactReplyService.new(
      conversation: conversation,
      content: incoming.content
    ).call
    return false unless known_fact&.exclusive?

    unless known_fact_already_delivered?(conversation, incoming, known_fact)
      Rails.logger.warn(
        "[Hermes::Callback] callback substituido por fato #{known_fact.kind} na conv #{conversation.display_id}"
      )
      deliver_outgoing(conversation, known_fact.content, known_fact.external_source)
    end
    head :ok
  end

  def known_fact_already_delivered?(conversation, incoming, known_fact)
    conversation.messages
                .where(message_type: :outgoing)
                .where('created_at > ?', incoming.created_at)
                .exists?(["#{Message.content_attribute_sql('external_source')} = ?", known_fact.external_source])
  end

  def handle_blocked_content(conversation, content)
    return handle_error_payload(conversation, content) if error_payload?(content)
    return handle_internal_status(conversation, content) if internal_status?(content)
    return handle_prompt_leak(conversation, content) if Captain::Guards::PromptLeak.leak?(content)

    false
  end

  def error_payload?(content)
    return false if content.blank?

    ERROR_PAYLOAD_PATTERNS.any? { |re| content.match?(re) }
  end

  def internal_status?(content)
    return false if content.blank?

    INTERNAL_STATUS_PATTERNS.any? { |re| content.match?(re) }
  end

  # Status de concorrência não significa falha do turno: a resposta final pode
  # chegar logo depois. Por isso bloqueamos o envio e registramos uma nota para
  # auditoria, sem abrir triagem humana nem cancelar o processamento atual.
  def handle_internal_status(conversation, content)
    Rails.logger.warn(
      "[Hermes::Callback] status interno barrado na conv #{conversation.display_id}: #{content.to_s.squish[0, 200]}"
    )

    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: conversation.inbox.captain_assistant,
      content: "⚠️ Status interno do Hermes bloqueado; o cliente NÃO recebeu isto:\n\n#{content}",
      content_attributes: { external_source: 'hermes_internal_status_blocked' }
    )

    head :ok
  end

  # O erro fica registrado como nota interna (visível só para a equipe) e a
  # conversa vai para triagem humana. O cliente não recebe nada — do ponto de
  # vista dele a IA ficou em silêncio, e uma pessoa assume.
  def handle_error_payload(conversation, content)
    Rails.logger.error(
      "[Hermes::Callback] payload de erro barrado na conv #{conversation.display_id}: #{content.to_s.squish[0, 200]}"
    )

    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: conversation.inbox.captain_assistant,
      content: "⚠️ A IA falhou e devolveu um erro técnico em vez de resposta. O cliente NÃO recebeu isto:\n\n#{content}",
      content_attributes: { external_source: 'hermes_error_blocked' }
    )

    mark_for_human_triage(conversation, reason: 'erro_tecnico')
    head :ok
  end

  # O LLM devolveu conteúdo interno em vez de resposta: pedaço do system prompt,
  # narração do que o assistente "deve" fazer, nome técnico de tool, JSON cru ou
  # Liquid não renderizado. Mesmo desfecho do payload de erro — o cliente não
  # recebe nada, a equipe vê o que foi barrado numa nota interna, e uma pessoa
  # assume a conversa.
  def handle_prompt_leak(conversation, content)
    reason = Captain::Guards::PromptLeak.reason(content)

    Rails.logger.error(
      "[Hermes::Callback] vazamento de prompt (#{reason}) barrado na conv " \
      "#{conversation.display_id}: #{content.to_s.squish[0, 200]}"
    )

    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: conversation.inbox.captain_assistant,
      content: "⚠️ A IA devolveu conteúdo interno em vez de resposta (#{reason}). " \
               "O cliente NÃO recebeu isto:\n\n#{content}",
      content_attributes: { external_source: 'hermes_prompt_leak_blocked' }
    )

    mark_for_human_triage(conversation, reason: 'vazamento_prompt')
    head :ok
  end

  # Hermes mandou frase-âncora de handoff: entrega ao cliente normalmente,
  # mas marca conv pra triagem humana — próximas msgs não disparam Hermes
  # de novo (guard em OutgoingJob). Loop real também escala, mas a resposta
  # repetida não é entregue ao cliente.
  def detect_handoff_or_loop(conversation, content)
    if handoff_response?(content)
      mark_for_human_triage(conversation, reason: 'sem_resposta_segura')
      false
    elsif looped_response?(conversation, content)
      mark_for_human_triage(conversation, reason: 'loop_detectado')
      true
    else
      false
    end
  end

  def deliver_outgoing(conversation, content, external_source = 'hermes_callback')
    if defined?(Captain::Hermes::DelayedReplyJob)
      args = [conversation.id, content]
      args << external_source unless external_source == 'hermes_callback'
      Captain::Hermes::DelayedReplyJob.perform_later(*args)
    else
      create_outgoing_message(conversation, content, external_source)
    end
  end

  def handoff_response?(content)
    return false if content.blank?

    HANDOFF_PATTERNS.any? { |re| content.match?(re) }
  end

  # Detecta loop: a resposta atual do Hermes é muito parecida com a anterior
  # outgoing dele na mesma conv (Jaccard de tokens >= 0.50). Sinaliza que o
  # agente está repetindo pergunta/resposta sem progredir — geralmente
  # cliente fora do escopo (operadora telefonia, banco, suporte de outro
  # app, etc) OU fluxo travado.
  def looped_response?(conversation, content)
    previous_responses = recent_hermes_responses(conversation)
    prev = previous_responses.first
    return false if prev.blank?

    return false if one_clarification_after_ambiguous_acknowledgement?(conversation, content, previous_responses)

    loop_like_response?(content, prev)
  end

  def recent_hermes_responses(conversation)
    conversation.messages
                .where(message_type: :outgoing)
                .where("#{Message.content_attribute_sql('external_source')} = ?", 'hermes_callback')
                .reorder(created_at: :desc)
                .limit(3)
                .pluck(:content)
  end

  # "Isso" ou "sim" depois de uma lista não contém a escolha necessária. A
  # primeira reformulação da pergunta deve chegar ao cliente; se ela repetir a
  # mesma pergunta depois de outra confirmação vaga, o contador abaixo deixa a
  # proteção normal de loop assumir a conversa.
  def one_clarification_after_ambiguous_acknowledgement?(conversation, content, previous_responses)
    return false unless ambiguous_acknowledgement?(conversation)
    return false if recent_ambiguous_acknowledgements(conversation) > 1

    previous_responses.count { |response| loop_like_response?(content, response) } == 1
  end

  def recent_ambiguous_acknowledgements(conversation)
    conversation.messages
                .where(message_type: :incoming)
                .reorder(created_at: :desc)
                .limit(3)
                .pluck(:content)
                .count do |content|
      normalized = ActiveSupport::Inflector.transliterate(content.to_s.downcase)
      ambiguous_short_reply?(normalized)
    end
  end

  def loop_like_response?(content, previous_response)
    return true if similarity(content, previous_response) >= LOOP_SIMILARITY_THRESHOLD

    repeated_question?(content, previous_response)
  end

  def ambiguous_acknowledgement?(conversation)
    last_customer_message = conversation.messages
                                        .where(message_type: :incoming)
                                        .reorder(created_at: :desc)
                                        .pick(:content)
    normalized = ActiveSupport::Inflector.transliterate(last_customer_message.to_s.downcase)
    ambiguous_short_reply?(normalized)
  end

  def ambiguous_short_reply?(normalized)
    AMBIGUOUS_ACKNOWLEDGEMENT_REGEX.match?(normalized) ||
      normalized.match?(/\A\s*(?:\?+|\p{Emoji_Presentation}+|\p{Extended_Pictographic}+)\s*\z/)
  end

  def similarity(text_a, text_b)
    set_a = tokenize(text_a)
    set_b = tokenize(text_b)
    return 0.0 if set_a.empty? || set_b.empty?

    intersection = (set_a & set_b).size
    union = (set_a | set_b).size
    intersection.to_f / union
  end

  # Compara a pergunta de uma resposta com a pergunta da outra. Repetir o
  # assunto é normal numa venda; repetir o pedido é que indica que a atendente
  # travou.
  def repeated_question?(text_a, text_b)
    question_a = last_inquisitive_sentence(text_a)
    question_b = last_inquisitive_sentence(text_b)
    return false if question_a.blank? || question_b.blank?

    similarity(question_a, question_b) >= LOOP_QUESTION_SIMILARITY
  end

  def last_inquisitive_sentence(text)
    text.to_s.split(/(?<=[.?!])\s+|\n+/).reverse.find { |sentence| inquisitive?(sentence) }
  end

  INQUISITIVE_REGEX = /(\?|\bme\s+confirm|\bvoce\s+(prefere|quer)|\bqual\s+(prefere|deseja|seria)|\bquer\s+(que|saber|ver|um|uma))/i

  def inquisitive?(text)
    INQUISITIVE_REGEX.match?(ActiveSupport::Inflector.transliterate(text.to_s))
  end

  def tokenize(text)
    normalized = ActiveSupport::Inflector.transliterate(text.to_s.downcase)
    normalized.scan(/[a-z0-9]+/).reject { |w| w.length < 3 }.to_set
  end

  def mark_for_human_triage(conversation, reason: nil)
    # Callbacks concorrentes do mesmo erro chegavam no mesmo instante e todos
    # liam a conversa antes de a primeira triagem ser gravada. O lock garante
    # uma única nota/etiqueta por conversa, inclusive para erro técnico.
    conversation.with_lock do
      conversation.reload
      reason_label = "triagem_#{reason}" if reason.present?
      current = conversation.label_list
      already_triaged = current.include?('triagem_humana')
      labels = (current + %w[triagem_humana] + [reason_label]).compact.uniq
      conversation.update!(status: :open) unless conversation.open?
      conversation.update_labels(labels)
      Captain::Hermes::HumanTriageNoteService.new(conversation: conversation, reason: reason).perform unless already_triaged
    end
    Rails.logger.info("[Hermes::Callback] conv #{conversation.display_id} → triagem_humana (#{reason})")
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
         .reorder(updated_at: :desc)
         .first
  end

  # Prefer an explicit conversation identifier sent back by Hermes/Captain.
  # The old fallback ("most recent conversation in the inbox") is unsafe when
  # several WhatsApp customers talk to the same attendant at the same time: a
  # delayed callback can be delivered into another customer's conversation.
  def conversation_from_callback(inbox) # rubocop:disable Metrics/AbcSize
    internal_id = params[:conversation_internal_id].presence || params.dig(:metadata, :conversation_internal_id).presence
    display_id = params[:conversation_id].presence || params.dig(:metadata, :conversation_id).presence

    if internal_id.present?
      conversation = inbox.conversations.find_by(id: internal_id)
      return conversation if conversation.present?

      Rails.logger.warn("[Hermes::Callback] explicit conversation_internal_id=#{internal_id} not found in inbox #{inbox.id}")
    end

    return nil if display_id.blank?

    conversation = inbox.conversations.find_by(display_id: display_id)
    Rails.logger.warn("[Hermes::Callback] explicit conversation_id=#{display_id} not found in inbox #{inbox.id}") if conversation.blank?
    conversation
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

  def create_outgoing_message(conversation, content, external_source = 'hermes_callback')
    assistant = conversation.inbox.captain_assistant
    sender = assistant.presence || User.find_by(id: conversation.assignee_id)

    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: sender,
      content: content,
      content_attributes: {
        external_source: external_source
      }
    )
  end
end
# rubocop:enable Metrics/ClassLength
