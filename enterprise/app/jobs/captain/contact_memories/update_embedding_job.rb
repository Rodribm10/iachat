class Captain::ContactMemories::UpdateEmbeddingJob < ApplicationJob
  queue_as :low

  retry_on Captain::Llm::EmbeddingService::EmbeddingsError, wait: :polynomially_longer, attempts: 3

  def perform(memory_id, run_contradiction_check: false)
    memory = Captain::ContactMemory.find_by(id: memory_id)
    return if memory.blank?

    embedding = Captain::Llm::EmbeddingService.new(account_id: memory.account_id).get_embedding(memory.content)
    return if embedding.blank?

    memory.update!(embedding: embedding)

    Captain::ContactMemories::ContradictionCheckerJob.perform_later(memory.id) if run_contradiction_check
  end
end
