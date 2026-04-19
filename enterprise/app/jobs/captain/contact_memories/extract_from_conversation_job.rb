class Captain::ContactMemories::ExtractFromConversationJob < ApplicationJob
  queue_as :low

  TTL_BY_TYPE = {
    'preferencia' => 365.days,
    'padrao_comportamental' => 365.days,
    'reclamacao' => 180.days,
    'feedback_positivo' => 365.days,
    'vinculo_social' => 730.days,
    'vinculo_comercial' => 365.days,
    'contexto_pessoal' => 365.days
    # data_comemorativa, restricao: no TTL (nil)
  }.freeze

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?
    return unless conversation.account.captain_contact_memory_extraction_enabled?
    return if already_extracted?(conversation)

    facts = Captain::ContactMemories::ExtractionService.new(conversation: conversation).call
    return if facts.blank?

    unit_id = resolve_unit_id(conversation)
    created_memory_ids = persist_all(facts, conversation, unit_id)
    enqueue_embedding_jobs(created_memory_ids)
  end

  private

  def already_extracted?(conversation)
    Captain::ContactMemory.exists?(source_conversation_id: conversation.id)
  end

  def persist_all(facts, conversation, unit_id)
    Captain::ContactMemory.transaction do
      facts.map { |fact| persist_fact(fact, conversation, unit_id).id }
    end
  end

  def enqueue_embedding_jobs(memory_ids)
    memory_ids.each do |id|
      Captain::ContactMemories::UpdateEmbeddingJob.perform_later(id, run_contradiction_check: true)
    end
  end

  def persist_fact(fact, conversation, unit_id)
    Captain::ContactMemory.create!(build_attributes(fact, conversation, unit_id))
  end

  def build_attributes(fact, conversation, unit_id)
    ttl = TTL_BY_TYPE[fact[:memory_type]]
    {
      account_id: conversation.account_id,
      contact_id: conversation.contact_id,
      memory_type: fact[:memory_type],
      content: fact[:content],
      evidence: fact[:evidence],
      confidence: fact[:confidence],
      scope: fact[:scope],
      source_conversation_id: conversation.id,
      source_unit_id: unit_id,
      source_inbox_id: conversation.inbox_id,
      last_verified_at: Time.current,
      expires_at: ttl&.from_now
    }
  end

  def resolve_unit_id(conversation)
    return conversation.captain_unit_id if conversation.respond_to?(:captain_unit_id) && conversation.captain_unit_id.present?

    Captain::Unit.where(inbox_id: conversation.inbox_id).pick(:id)
  end
end
