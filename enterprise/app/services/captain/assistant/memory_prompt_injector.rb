class Captain::Assistant::MemoryPromptInjector
  def initialize(conversation:)
    @conversation = conversation
  end

  def recall_enabled?
    account = @conversation&.account
    return false if account.blank?

    account.respond_to?(:captain_contact_memory_recall_enabled?) &&
      account.captain_contact_memory_recall_enabled?
  end

  # Wraps the given base system prompt with a <memoria_cliente> block
  # when recall is enabled and memories are found. Degrades gracefully:
  # returns the untouched base prompt on any failure or absent context.
  def append_memory_block(base_prompt, message_text)
    return base_prompt unless recall_enabled?
    return base_prompt if @conversation&.contact.blank?

    memories = Captain::ContactMemories::RecallService.new(
      contact: @conversation.contact,
      query_text: message_text,
      unit_id: resolve_unit_id
    ).call

    memory_block = Captain::ContactMemories::PromptInjectionService.new(memories: memories).call
    return base_prompt if memory_block.blank?

    [base_prompt, memory_block].join("\n\n")
  end

  private

  def resolve_unit_id
    return nil if @conversation.blank?

    return @conversation.captain_unit_id if @conversation.respond_to?(:captain_unit_id) && @conversation.captain_unit_id.present?

    Captain::Unit.where(inbox_id: @conversation.inbox_id).pick(:id) if defined?(Captain::Unit)
  rescue StandardError => e
    Rails.logger.warn("[Captain V2] MemoryPromptInjector#resolve_unit_id failed: #{e.message}")
    nil
  end
end
