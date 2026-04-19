class Captain::Assistant::MemoryPromptInjector
  CACHED_MEMORY_KEY = 'captain_cached_memory_block'.freeze
  CACHED_CONTACT_KEY = 'captain_cached_memory_contact_id'.freeze

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
    # Conversation-level cache: once the memory block is computed for this
    # conversation (usually on the first message), reuse it for every
    # subsequent turn until the conversation is resolved. The customer's
    # profile does not change during an open conversation, so re-running
    # embedding + pgvector on every turn is pure waste.
    cached = conversation_level_cache
    return cached if cached.present?

    # In-memory fallback cache (per-service-instance) for edge cases where
    # the conversation_level_cache write fails and we still want to avoid
    # re-hitting the API within a single job execution.
    key = message_text.to_s
    return @memory_block_cache[key] if @memory_block_cache.key?(key)

    memories = Captain::ContactMemories::RecallService.new(
      contact: @conversation.contact,
      query_text: key,
      unit_id: resolve_unit_id
    ).call

    block = Captain::ContactMemories::PromptInjectionService.new(memories: memories).call
    @memory_block_cache[key] = block
    persist_conversation_level_cache(block)
    block
  end

  # Reads the pre-computed memory block stashed on the conversation.
  # Returns nil when missing, empty, or stale (different contact). Callers
  # still get a fresh recall in those cases.
  def conversation_level_cache
    return nil if @conversation.blank?

    raw = @conversation.custom_attributes.to_h[CACHED_MEMORY_KEY]
    return nil if raw.blank?

    cached_contact_id = @conversation.custom_attributes.to_h[CACHED_CONTACT_KEY]
    return nil if cached_contact_id.present? && cached_contact_id.to_i != @conversation.contact_id.to_i

    raw.to_s
  rescue StandardError => e
    Rails.logger.warn("[Captain V2] MemoryPromptInjector read cache failed: #{e.message}")
    nil
  end

  # Stores the computed block on the conversation so future turns reuse it.
  # Stored as a custom_attribute to avoid a new column. The resolve-conversation
  # listener in Phase 4 already fires ExtractFromConversationJob — a future
  # enhancement can clear this cache on resolve, but letting it live is
  # harmless (next conversation is a new record with empty custom_attributes).
  def persist_conversation_level_cache(block)
    return if @conversation.blank? || block.to_s.empty?

    attrs = @conversation.custom_attributes.to_h
    attrs[CACHED_MEMORY_KEY] = block
    attrs[CACHED_CONTACT_KEY] = @conversation.contact_id
    # rubocop:disable Rails/SkipsModelValidations
    # update_columns deliberately — this cache write runs on every turn
    # and must not trigger callbacks (which could re-enqueue heavy jobs).
    @conversation.update_columns(custom_attributes: attrs)
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[Captain V2] MemoryPromptInjector write cache failed: #{e.message}")
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
