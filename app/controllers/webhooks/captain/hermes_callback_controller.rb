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
class Webhooks::Captain::HermesCallbackController < ApplicationController # rubocop:disable Metrics/ClassLength
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

  # Camada 2 — Gating de saída factual:
  # Se a resposta do Hermes contém info factual (preço, senha, regra,
  # horário) E o LLM NÃO chamou nenhuma tool MCP entre o dispatch e o
  # callback, é alucinação de memória. Bloqueia a resposta, força
  # consulta a tool via notify_event. 1 retry; se persistir, escala humano.
  FACTUAL_PATTERNS = [
    /R\$\s*\d/i,                                                # R$ 50, R$ 125,00
    /\b\d+\s*(reais|reai|real)\b/i,
    /\b\d+\s*%/,                                                # 50%
    /\bsenha\b/i,                                               # qualquer menção a senha
    /\b(c[óo]digo)\s+(de|do)\s+(porta|portao|portão|garagem)\b/i,
    /\b(check[-]?in|check[-]?out|hor[áa]rio)\s+(é|eh|de)\s+\d/i, # check-in é 14h
    /\b(política|politica|regra)\s+de\s+(cancelamento|no[\s-]?show|reembolso)/i,
    /(n[ãa]o\s+(é\s+)?permitido|é\s+permitido)\s+\w{3,}/i,
    /(pode|podem)\s+(levar|trazer)\s+(animal|pet|cachorro|gato|crian[çc]a)/i
  ].freeze
  MAX_FACTUAL_GATE_RETRIES = 1

  # Loop detection: 2 sinais combinados.
  # 1. Jaccard de tokens >= 0.50 → resposta praticamente igual.
  # 2. >= 3 palavras-chave em comum (sem stopwords) E ambas terminam com
  #    "?" → repetiu pergunta sobre o mesmo tópico (caso clássico do
  #    "endereço completo ou link?" → "apenas link ou link + endereço?").
  LOOP_SIMILARITY_THRESHOLD = 0.50
  LOOP_TOPIC_KEYWORD_OVERLAP = 3
  LOOP_STOPWORDS = %w[
    voce voces para por pra como mas isso esse essa estou esta este aqui ali
    eles elas tem ter tinha tendo era ser sou foi fui agora ainda ja muito mais
    quer quero queria pode posso podia consegue consigo conseguia preciso precisar
    sim nao não talvez bom boa olha veja oi ola ola tchau certo ok blz beleza
    obrigado obrigada valeu vlw thanks por favor please
    apenas somente algum alguma quem onde quando o a os as do da dos das no na nos nas
    em com sem sob sobre antes apos depois entre meio tudo todo toda
    perfeito otimo certinho confirma confirme
  ].freeze

  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_signature
  before_action :fetch_inbox

  def process_payload
    content = extract_content
    return head :bad_request if content.blank?

    conversation = recent_conversation_for(@inbox)
    return log_no_conversation_and_ack if conversation.blank?

    log_reply(conversation, content)

    # Camada 2: resposta factual sem chamada de tool durante a turn é
    # alucinação de memória. Bloqueia entrega + re-dispara forçando tool
    # call. NÃO entrega a msg pro cliente até o LLM consultar a fonte.
    return head :ok if gate_factual_no_tool!(conversation, content)

    detect_handoff_or_loop(conversation, content)
    deliver_outgoing(conversation, content)
    head :ok
  rescue StandardError => e
    Rails.logger.error "[Hermes::Callback] error: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    head :internal_server_error
  end

  # Hermes mandou frase-âncora de handoff: entrega ao cliente normalmente,
  # mas marca conv pra triagem humana — próximas msgs não disparam Hermes
  # de novo (guard em OutgoingJob). OU: detectou loop (mesma resposta /
  # pergunta reformulada) e escala.
  def detect_handoff_or_loop(conversation, content)
    if handoff_response?(content)
      mark_for_human_triage(conversation, reason: 'handoff_intencional')
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

  private

  def handoff_response?(content)
    return false if content.blank?

    HANDOFF_PATTERNS.any? { |re| content.match?(re) }
  end

  # Retorna true se bloqueou a resposta (callback deve dar 200 + sair sem
  # entregar). Retorna false pra fluxo normal continuar.
  def gate_factual_no_tool!(conversation, content)
    return false unless looks_factual?(content)
    return false if tool_called_in_this_turn?(conversation)

    retry_key = "hermes_factual_gate_retry:#{conversation.id}"
    retries = Rails.cache.read(retry_key, raw: true).to_i
    if retries >= MAX_FACTUAL_GATE_RETRIES
      Rails.logger.error("[Hermes::Callback] factual sem tool persistente em conv #{conversation.display_id} — escalando")
      mark_for_human_triage(conversation, reason: 'factual_no_tool_persistente')
      Rails.cache.delete(retry_key)
      # Entrega o conteúdo nesse caso (melhor algo do que silêncio); humano vê pela label.
      deliver_outgoing(conversation, content)
      return true
    end

    Rails.cache.write(retry_key, retries + 1, expires_in: 5.minutes, raw: true)
    Rails.logger.warn("[Hermes::Callback] factual sem tool em conv #{conversation.display_id} — re-dispatch (retry #{retries + 1})")
    trigger_force_tool_call!(conversation, content)
    true
  end

  def looks_factual?(content)
    return false if content.blank?

    FACTUAL_PATTERNS.any? { |re| content.match?(re) }
  end

  # Compara contador de tool calls atual com baseline gravado pelo
  # OutgoingJob no momento do dispatch. Se subiu, o LLM chamou tool —
  # resposta é fundamentada. Se igual, é puro palpite.
  def tool_called_in_this_turn?(conversation)
    baseline = Rails.cache.read("hermes_tool_calls_baseline:#{conversation.id}", raw: true).to_i
    current = Rails.cache.read("hermes_tool_calls:#{conversation.id}", raw: true).to_i
    current > baseline
  end

  def trigger_force_tool_call!(conversation, original_content)
    Captain::Hermes::Client.new(@inbox).notify_event(
      conversation: conversation,
      event_type: 'force_factual_tool',
      system_message: '[SISTEMA: force_factual_tool] Você emitiu uma resposta com info ' \
                      "factual ('#{original_content.truncate(120)}') SEM consultar tool. " \
                      'Cliente NÃO recebeu essa mensagem. Releia a última pergunta do ' \
                      'cliente e CHAME a tool relevante AGORA: faq_lookup pra regra/' \
                      'política/Wi-Fi/horário, tabela de preços da skill pra valores. ' \
                      'Se a tool retornar vazio, NÃO INVENTE: responda exatamente ' \
                      "'⏳ Um momento — vou verificar.' e pare."
    )
  rescue Captain::Hermes::Client::DispatchError => e
    Rails.logger.error("[Hermes::Callback] force_factual_tool dispatch falhou: #{e.message}")
    mark_for_human_triage(conversation, reason: 'force_factual_dispatch_falhou')
    deliver_outgoing(conversation, original_content)
  end

  # Detecta loop: a resposta atual do Hermes é muito parecida com a anterior
  # outgoing dele na mesma conv (Jaccard de tokens >= 0.70). Sinaliza que o
  # agente está repetindo pergunta/resposta sem progredir — geralmente
  # cliente fora do escopo OU fluxo travado (pediu link sem ter como
  # entregar, perguntou de novo a mesma confirmação, etc).
  def looped_response?(conversation, content)
    prev = conversation.messages
                       .where(message_type: :outgoing)
                       .where("content_attributes ->> 'external_source' = ?", 'hermes_callback')
                       .order(created_at: :desc)
                       .limit(1)
                       .pick(:content)
    return false if prev.blank?

    return true if similarity(content, prev) >= LOOP_SIMILARITY_THRESHOLD

    # Caso "pergunta reformulada sobre o mesmo tópico": ambas terminam com "?"
    # e compartilham >= 3 palavras-chave (sem stopwords).
    repeated_question?(content, prev)
  end

  def similarity(text_a, text_b)
    set_a = tokenize(text_a)
    set_b = tokenize(text_b)
    return 0.0 if set_a.empty? || set_b.empty?

    intersection = (set_a & set_b).size
    union = (set_a | set_b).size
    intersection.to_f / union
  end

  # Pergunta/confirmação reformulada sobre o mesmo tópico. Detecta tanto "?"
  # quanto formas imperativas comuns ("me confirma", "qual", "quer").
  def repeated_question?(text_a, text_b)
    return false unless inquisitive?(text_a) && inquisitive?(text_b)

    keywords_a = tokenize(text_a) - LOOP_STOPWORDS
    keywords_b = tokenize(text_b) - LOOP_STOPWORDS
    (keywords_a & keywords_b).size >= LOOP_TOPIC_KEYWORD_OVERLAP
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
    current = conversation.label_list
    conversation.update_labels((current + %w[triagem_humana]).uniq)
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
