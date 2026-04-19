class Captain::ContactMemories::ContradictionCheckerJob < ApplicationJob
  queue_as :low

  def perform(memory_id)
    memory = Captain::ContactMemory.find_by(id: memory_id)
    return if memory.blank?

    Captain::ContactMemories::ContradictionCheckerService.new(memory: memory).call
  end
end
