class Captain::ContactMemories::ContradictionCheckerJob < ApplicationJob
  queue_as :low

  # TODO(phase3-task3.2): implement full contradiction detection logic.
  # This skeleton exists so Captain::ContactMemories::UpdateEmbeddingJob can
  # enqueue it when run_contradiction_check is true. Task 3.2 will replace
  # the body with the real implementation.
  def perform(memory_id)
    memory = Captain::ContactMemory.find_by(id: memory_id)
    return if memory.blank?

    # no-op until task 3.2
  end
end
