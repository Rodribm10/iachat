class Captain::ContactMemories::RecallService
  TIMEOUT_SECONDS = 2.0
  DEFAULT_TOP_K = 5

  def initialize(contact:, query_text:, unit_id: nil, top_k: DEFAULT_TOP_K)
    @contact = contact
    @query_text = query_text
    @unit_id = unit_id
    @top_k = top_k
  end

  def call
    return [] if @contact.blank? || @query_text.blank?

    # NOTE: Timeout.timeout is used here as a hard cap on both embedding API + DB query.
    # It has known hazards (async exception, can't cleanly interrupt C-level I/O, can
    # corrupt connection state) — tradeoff accepted because this service is non-critical:
    # any failure returns [] and the agent degrades gracefully without memory. Phase 6
    # will consider refactoring the DB portion to Postgres statement_timeout for safer
    # cancellation.
    Timeout.timeout(TIMEOUT_SECONDS) do
      query_embedding = Captain::Llm::EmbeddingService.new(account_id: @contact.account_id).get_embedding(@query_text)
      return [] if query_embedding.blank?

      nearest_memories(query_embedding)
    end
  rescue StandardError => e
    log_failure(e)
    []
  end

  private

  def nearest_memories(query_embedding)
    Captain::ContactMemory
      .active
      .for_contact(@contact.id)
      .scope_compatible(@unit_id)
      .where.not(embedding: nil)
      .nearest_neighbors(:embedding, query_embedding, distance: 'cosine')
      .limit(@top_k)
      .to_a
  end

  def log_failure(error)
    Rails.logger.warn(
      "[ContactMemory::RecallService] #{error.class}: #{error.message} " \
      "(contact_id=#{@contact&.id} account_id=#{@contact&.account_id})"
    )
    Rails.logger.warn(error.backtrace.first(5).join("\n")) unless error.is_a?(Timeout::Error)
  end
end
