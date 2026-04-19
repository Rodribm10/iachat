class Captain::ContactMemories::ExtractionService
  MAX_FACTS = 5
  MIN_CONFIDENCE = 0.5
  EXTRACTION_MODEL = 'gpt-4o-mini'.freeze
  MAX_CHARS = 40_000 # matches Captain::Llm::ConversationInsightService convention
  SCOPE_PATTERN = /\A(global|unit:\d+)\z/

  def initialize(conversation:)
    @conversation = conversation
  end

  def call
    raw = call_llm
    parsed = JSON.parse(raw)
    facts = parsed.fetch('facts', [])
    facts.filter_map { |f| normalize(f) }.take(MAX_FACTS)
  rescue JSON::ParserError => e
    Rails.logger.warn("[ContactMemory::ExtractionService] JSON parse: #{e.message}")
    []
  rescue StandardError => e
    Rails.logger.error("[ContactMemory::ExtractionService] #{e.class}: #{e.message}")
    []
  end

  private

  # TODO(phase-6): add Integrations::LlmInstrumentation wrap for OTEL metrics
  # (extraction_count, extraction_cost, facts_per_call, llm_error_rate).
  def call_llm
    RubyLLM.chat(model: EXTRACTION_MODEL)
           .with_temperature(0)
           .with_params(response_format: { type: 'json_object' })
           .ask(build_prompt)
           .content.to_s
  end

  def build_prompt
    <<~PROMPT
      Você é um analista que extrai FATOS MEMORÁVEIS de uma conversa de WhatsApp entre um hóspede e um hotel.

      Taxonomia (SÓ use estes tipos, caso contrário descarte o fato):
      #{Captain::ContactMemory::MEMORY_TYPES.join(', ')}

      Para cada fato, retorne JSON com:
      - memory_type (um dos tipos acima)
      - content (frase curta, português, max 1000 chars)
      - evidence (trecho LITERAL da conversa que sustenta o fato — obrigatório)
      - confidence (0.0 a 1.0)
      - scope ('global' na maioria dos casos; 'unit:<id>' só se o fato for operacional de uma unidade específica)

      Regras INVIOLÁVEIS:
      1. Se não houver evidência textual clara, NÃO extraia o fato.
      2. Máximo 5 fatos por conversa. Extraia só os realmente memoráveis.
      3. Se a conversa não tem nada memorável, retorne {"facts": []}.
      4. Nunca invente fatos. Se em dúvida, descarte.

      Conversa:
      #{formatted_messages}

      Retorne JSON no formato: {"facts": [{...}, ...]}
    PROMPT
  end

  # Feeds the LLM extractor. MUST exclude:
  # - private: true (internal agent-to-agent notes — never seen by the guest; privacy leak if extracted)
  # - failed status (outbound messages that never reached the guest — extracting from them is dishonest)
  def formatted_messages
    scope = @conversation.messages
                         .where(message_type: [:incoming, :outgoing], private: false)
                         .where.not(status: :failed)
                         .order(created_at: :asc)

    limited_messages(scope).map { |m| "[#{m.message_type}] #{m.content}" }.join("\n")
  end

  def limited_messages(scope)
    all = scope.to_a
    return all if all.sum { |m| m.content.to_s.length } <= MAX_CHARS

    # keep most recent messages, drop oldest until under cap
    kept = []
    total = 0
    all.reverse_each do |msg|
      len = msg.content.to_s.length
      break if total + len > MAX_CHARS

      kept.unshift(msg)
      total += len
    end
    kept
  end

  def normalize(raw_fact)
    type = raw_fact['memory_type'].to_s
    content = raw_fact['content'].to_s.strip
    evidence = raw_fact['evidence'].to_s.strip
    confidence = raw_fact['confidence'].to_f
    raw_scope = raw_fact['scope'].to_s.presence || 'global'
    scope = valid_scope?(raw_scope) ? raw_scope : 'global'

    return nil unless Captain::ContactMemory::MEMORY_TYPES.include?(type)
    return nil if content.blank? || evidence.blank?
    return nil if confidence < MIN_CONFIDENCE

    {
      memory_type: type,
      content: content.truncate(1000),
      evidence: evidence,
      confidence: confidence,
      scope: scope
    }
  end

  def valid_scope?(value)
    SCOPE_PATTERN.match?(value)
  end
end
