class Captain::ContactMemories::SilenceDetectorJob < ApplicationJob
  queue_as :scheduled_jobs

  SILENCE_THRESHOLD = 30.minutes

  def perform
    Account.where("custom_attributes->>'captain_contact_memory_extraction_enabled' = 'true'").find_each do |account|
      process_account(account)
    rescue StandardError => e
      Rails.logger.error("[SilenceDetectorJob] account=#{account.id} failed: #{e.class}: #{e.message}")
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
  end

  private

  def process_account(account)
    eligible_conversation_ids(account).each do |conv_id|
      Captain::ContactMemories::ExtractFromConversationJob.perform_later(conv_id)
    end
  end

  # Intentionally no `.where('messages.created_at < ?', SILENCE_THRESHOLD.ago)` pre-filter here:
  # that would let a conversation with ANY old message + a recent one be incorrectly
  # classified as silent. The HAVING MAX(...) clause alone is the correct semantics.
  # If this full-join becomes a perf issue at scale, rewrite as NOT EXISTS subquery.
  def eligible_conversation_ids(account)
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
