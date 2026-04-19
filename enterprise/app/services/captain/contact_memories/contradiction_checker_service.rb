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
      .select { |c| cosine_distance(c) < DISTANCE_THRESHOLD }
  end

  def cosine_distance(other)
    other.neighbor_distance
  end

  def contradicts?(fact_a, fact_b)
    response = RubyLLM.chat(model: CHECK_MODEL).with_temperature(0).ask(<<~PROMPT).content.to_s.downcase
      Estes 2 fatos sobre o mesmo cliente se contradizem?
      Fato A: "#{fact_a.content}"
      Fato B: "#{fact_b.content}"
      Responda apenas "sim" ou "nao".
    PROMPT
    response.include?('sim')
  rescue StandardError => e
    Rails.logger.warn("[ContradictionChecker] #{e.class}: #{e.message}")
    false
  end
end
