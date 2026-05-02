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

  # "Um momento — vou verificar" é a frase-âncora de handoff intencional
  # (quando o agente não sabe responder e quer escalar pra humano). NÃO
  # bloqueamos — entregamos pro cliente e marcamos triagem_humana pra
  # próximas msgs não dispararem Hermes.
  HANDOFF_PATTERNS = [
    /\A\s*[⏳⌛]?\s*um\s+momento.*verificar/i,
    /\A\s*[⏳⌛]?\s*um\s+instante.*verificar/i,
    /\A\s*aguarde\s+um\s+instante/i
  ].freeze

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
