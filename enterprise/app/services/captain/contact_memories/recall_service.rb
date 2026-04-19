class Captain::ContactMemories::RecallService
  TIMEOUT_SECONDS = 0.5
  DEFAULT_TOP_K = 5

  def initialize(contact:, query_text:, unit_id: nil, top_k: DEFAULT_TOP_K)
    @contact = contact
    @query_text = query_text
    @unit_id = unit_id
    @top_k = top_k
  end

  def call
    return [] if @contact.blank? || @query_text.blank?

    Timeout.timeout(TIMEOUT_SECONDS) do
      query_embedding = Captain::Llm::EmbeddingService.new(account_id: @contact.account_id).get_embedding(@query_text)
      return [] if query_embedding.blank?

      Captain::ContactMemory
        .active
        .for_contact(@contact.id)
        .scope_compatible(@unit_id)
        .where.not(embedding: nil)
        .nearest_neighbors(:embedding, query_embedding, distance: 'cosine')
        .limit(@top_k)
        .to_a
    end
  rescue StandardError => e
    Rails.logger.warn("[ContactMemory::RecallService] #{e.class}: #{e.message}")
    []
  end
end
