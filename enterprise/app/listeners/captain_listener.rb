class CaptainListener < BaseListener
  include ::Events::Types

  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    return if conversation.blank?

    Captain::ContactMemories::ExtractFromConversationJob.perform_later(conversation.id)
    # Recalcula indicadores de retenção (interações, recorrência, days_since)
    # agora que a conversa se encerrou e temos estado estável.
    Captain::Retention::RecalculateContactStatsJob.perform_later(conversation.contact_id) if conversation.contact_id.present?

    assistant = conversation.inbox.captain_assistant

    return unless conversation.inbox.captain_active?

    Captain::Llm::ContactNotesService.new(assistant, conversation).generate_and_update_notes if assistant.config['feature_memory'].present?
    Captain::Llm::ConversationFaqService.new(assistant, conversation).generate_and_deduplicate if assistant.config['feature_faq'].present?
  end
end
