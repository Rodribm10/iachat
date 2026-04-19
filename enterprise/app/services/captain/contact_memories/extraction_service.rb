class Captain::ContactMemories::ExtractionService
  MAX_FACTS = 5
  MIN_CONFIDENCE = 0.5
  EXTRACTION_MODEL = 'gpt-4o-mini'.freeze

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

  def call_llm
    response = RubyLLM.chat(model: EXTRACTION_MODEL)
                      .with_temperature(0)
                      .with_params(response_format: { type: 'json_object' })
                      .ask(build_prompt)
    response.content.to_s
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

  def formatted_messages
    @conversation.messages
                 .where(message_type: [:incoming, :outgoing], private: false)
                 .order(created_at: :asc)
                 .map { |m| "[#{m.message_type}] #{m.content}" }
                 .join("\n")
  end

  def normalize(raw_fact)
    type = raw_fact['memory_type'].to_s
    content = raw_fact['content'].to_s.strip
    evidence = raw_fact['evidence'].to_s.strip
    confidence = raw_fact['confidence'].to_f
    scope = raw_fact['scope'].to_s.presence || 'global'

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
end
