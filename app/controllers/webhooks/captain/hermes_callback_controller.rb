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
  #
  # Ancorado em INÍCIO DE LINHA (^), não em início de mensagem (\A): o prompt
  # manda mandar só a frase, mas o LLM às vezes responde o que sabe e fecha com
  # a âncora numa linha final. Com \A isso não casava — o cliente lia "vou
  # verificar", a conversa continuava em `pending` e nenhum humano era chamado.
  # Visto na conv 17 da academia em 23/08/2026, e o mesmo padrão vale para os
  # perfis de hotel, que rodam esta mesma regra.
  HANDOFF_PATTERNS = [
    /^\s*[⏳⌛]?\s*um\s+momento\b.*verificar/i,
    /^\s*[⏳⌛]?\s*um\s+instante\b.*verificar/i,
    /^\s*aguarde\s+um\s+instante/i
  ].freeze

  # Loop detection.
  #
  # A triagem existe para quando a IA NÃO SABE responder — e disso ela já
  # avisa sozinha, pela frase-âncora de handoff ou chamando a tool `handoff`.
  # Comparar o TEXTO de duas respostas para adivinhar que ela travou não mede
  # isso: num atendimento, parecido é o normal. Saudação responde saudação,
  # pergunta de preço responde preço. Com o limiar em duas respostas parecidas,
  # 633 conversas foram para triagem — e a triagem BLOQUEIA a IA nas mensagens
  # seguintes (guard no OutgoingJob), então cada falso positivo mata uma
  # conversa. Caso real: conv 126 da academia em 03/09/2026, o cliente mandou
  # "Ola" e depois "Boa noite Duda", a IA cumprimentou de volta as duas vezes
  # e foi barrada nas duas.
  #
  # Loop de verdade é a IA REPETINDO A MESMA resposta e sem sair do lugar. Por
  # isso agora exigimos LOOP_REPEAT_THRESHOLD respostas seguidas praticamente
  # idênticas — não duas vagamente parecidas.
  LOOP_SIMILARITY_THRESHOLD = 0.85
  LOOP_REPEAT_THRESHOLD = 3

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
    # Aviso do próprio gateway do Hermes (reinício/parada). Em 23/08/2026 o
    # cliente da academia leu "⚠️ Gateway shutting down — Your current task
    # will be interrupted." no WhatsApp.
    /gateway\s+shutting\s+down/i,
    /current\s+task\s+will\s+be\s+interrupted/i,
    # Erro genérico do runtime do Hermes. Não traz código HTTP nem nome de
    # exceção, então não casava com nenhum padrão acima e ATRAVESSOU: entre
    # 28/08 e 03/09/2026, 52 clientes da academia leram no WhatsApp "Sorry, I
    # encountered an unexpected error. Try again or use /reset to start a
    # fresh session." — em inglês, numa operação 100% pt-BR.
    /encountered\s+an\s+unexpected\s+error/i,
    %r{use\s+/reset\s+to\s+start}i,
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
    return if handle_blocked_content(conversation, content)

    detect_handoff_or_loop(conversation, content)
    deliver_outgoing(conversation, content)
    head :ok
  rescue StandardError => e
    Rails.logger.error "[Hermes::Callback] error: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    head :internal_server_error
  end

  private

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
  # de novo (guard em OutgoingJob). OU: detectou loop (mesma resposta /
  # pergunta reformulada) e escala.
  def detect_handoff_or_loop(conversation, content)
    if handoff_response?(content)
      mark_for_human_triage(conversation, reason: 'sem_resposta_segura')
    elsif looped_response?(conversation, content)
      mark_for_human_triage(conversation, reason: 'loop_detectado')
    end
  end

  def deliver_outgoing(conversation, content)
    if defined?(Captain::Hermes::DelayedReplyJob)
      Captain::Hermes::DelayedReplyJob.perform_later(conversation.id, content)
    else
      create_outgoing_message(conversation, content)
    end
  end

  def handoff_response?(content)
    return false if content.blank?

    HANDOFF_PATTERNS.any? { |re| content.match?(re) }
  end

  # A IA repetiu a MESMA resposta nas últimas LOOP_REPEAT_THRESHOLD vezes?
  # Só isso conta como travada. Duas respostas parecidas são conversa normal.
  def looped_response?(conversation, content)
    anteriores = conversation.messages
                             .where(message_type: :outgoing)
                             .where("#{Message.content_attribute_sql('external_source')} = ?", 'hermes_callback')
                             .reorder(created_at: :desc)
                             .limit(LOOP_REPEAT_THRESHOLD - 1)
                             .pluck(:content)
    return false if anteriores.size < LOOP_REPEAT_THRESHOLD - 1
    return false if anteriores.any?(&:blank?) || content.blank?

    ([content] + anteriores).each_cons(2).all? do |atual, anterior|
      similarity(atual, anterior) >= LOOP_SIMILARITY_THRESHOLD
    end
  end

  def similarity(text_a, text_b)
    set_a = tokenize(text_a)
    set_b = tokenize(text_b)
    return 0.0 if set_a.empty? || set_b.empty?

    intersection = (set_a & set_b).size
    union = (set_a | set_b).size
    intersection.to_f / union
  end

  def tokenize(text)
    normalized = ActiveSupport::Inflector.transliterate(text.to_s.downcase)
    normalized.scan(/[a-z0-9]+/).reject { |w| w.length < 3 }.to_set
  end

  # Rede de segurança do caminho determinístico: quando o assistente escreve a
  # frase-âncora em vez de chamar a tool `handoff`, o desfecho tem que ser o
  # mesmo. Por isso os dois caminhos passam pelo mesmo serviço.
  def mark_for_human_triage(conversation, reason: nil)
    Captain::Hermes::HumanTriageService.perform(conversation: conversation, reason: reason)
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
# rubocop:enable Metrics/ClassLength
