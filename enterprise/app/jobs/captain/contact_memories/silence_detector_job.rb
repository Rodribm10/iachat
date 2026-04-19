class Captain::ContactMemories::SilenceDetectorJob < ApplicationJob
  queue_as :scheduled_jobs

  SILENCE_THRESHOLD = 30.minutes

  def perform
    Account.where("custom_attributes->>'captain_contact_memory_extraction_enabled' = 'true'").find_each do |account|
      elegible_conversation_ids(account).each do |conv_id|
        Captain::ContactMemories::ExtractFromConversationJob.perform_later(conv_id)
      end
    end
  end

  private

  def elegible_conversation_ids(account)
    Conversation
      .where(account_id: account.id)
      .joins(:messages)
      .where.not(id: already_extracted_ids(account))
      .group('conversations.id')
      .having('MAX(messages.created_at) < ?', SILENCE_THRESHOLD.ago)
      .pluck(:id)
  end

  def already_extracted_ids(account)
    Captain::ContactMemory
      .where(account_id: account.id)
      .where.not(source_conversation_id: nil)
      .distinct
      .pluck(:source_conversation_id)
  end
end
