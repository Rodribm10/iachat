class Captain::Assistant::MemoryPromptInjector
  def initialize(conversation:)
    @conversation = conversation
    @memory_block_cache = {}
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
  # Caches the memory block per-message-text within the injector instance so
  # Agents::Runner evaluating instructions multiple times per turn does not
  # re-hit EmbeddingService or pgvector on every call.
  def append_memory_block(base_prompt, message_text)
    return base_prompt unless recall_enabled?
    return base_prompt if @conversation&.contact.blank?

    block = memory_block_for(message_text)
    return base_prompt if block.blank?

    [base_prompt, block].join("\n\n")
  rescue StandardError => e
    # Absolute guard: memory recall NEVER blocks or breaks the agent response.
    Rails.logger.error("[Captain V2] MemoryPromptInjector unexpected failure: #{e.class}: #{e.message}")
    base_prompt
  end

  private

  def memory_block_for(message_text)
    key = message_text.to_s
    return @memory_block_cache[key] if @memory_block_cache.key?(key)

    memories = Captain::ContactMemories::RecallService.new(
      contact: @conversation.contact,
      query_text: key,
      unit_id: resolve_unit_id
    ).call

    @memory_block_cache[key] =
      Captain::ContactMemories::PromptInjectionService.new(memories: memories).call
  end

  def resolve_unit_id
    return nil if @conversation.blank?

    return @conversation.captain_unit_id if @conversation.respond_to?(:captain_unit_id) && @conversation.captain_unit_id.present?

    Captain::Unit.where(inbox_id: @conversation.inbox_id).pick(:id) if defined?(Captain::Unit)
  rescue StandardError => e
    Rails.logger.warn("[Captain V2] MemoryPromptInjector#resolve_unit_id failed: #{e.message}")
    nil
  end
end
