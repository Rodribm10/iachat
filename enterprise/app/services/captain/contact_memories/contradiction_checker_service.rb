class Captain::ContactMemories::ContradictionCheckerService
  MAX_CANDIDATES = 3
  DISTANCE_THRESHOLD = 0.6
  CHECK_MODEL = 'gpt-4o-mini'.freeze

  def initialize(memory:)
    @memory = memory
  end

  def call
    return if @memory.embedding.blank?

    candidates.each do |candidate|
      candidate.supersede_by!(@memory) if contradicts?(candidate, @memory)
    end
  rescue StandardError => e
    Rails.logger.error("[ContradictionChecker] call failed: #{e.class}: #{e.message} (memory_id=#{@memory&.id})")
  end

  private

  def candidates
    Captain::ContactMemory
      .active
      .for_contact(@memory.contact_id)
      .by_type(@memory.memory_type)
      .where.not(id: @memory.id)
      .where.not(embedding: nil)
      .nearest_neighbors(:embedding, @memory.embedding, distance: 'cosine')
      .first(MAX_CANDIDATES)
      .select { |c| c.neighbor_distance < DISTANCE_THRESHOLD }
  end

  def contradicts?(fact_a, fact_b)
    answer = query_llm_for_contradiction(fact_a, fact_b)
    answer == 'sim'
  rescue StandardError => e
    Rails.logger.warn("[ContradictionChecker] #{e.class}: #{e.message}")
    false
  end

  def query_llm_for_contradiction(fact_a, fact_b)
    response = RubyLLM.chat(model: CHECK_MODEL).with_temperature(0).ask(contradiction_prompt(fact_a, fact_b)).content.to_s
    # Extract the first meaningful word. Expected "sim" or "nao" (or "não").
    first_word = response.strip.downcase.gsub(/[^a-zãáéíóúç]/, ' ').split.first.to_s
    # Normalize "não" → "nao" for ASCII comparison
    first_word.tr('ãáéíóúç', 'aaeiouc')
  end

  def contradiction_prompt(fact_a, fact_b)
    <<~PROMPT
      Estes 2 fatos sobre o mesmo cliente se contradizem?
      Fato A: "#{fact_a.content}"
      Fato B: "#{fact_b.content}"
      Responda apenas "sim" ou "nao".
    PROMPT
  end
end
