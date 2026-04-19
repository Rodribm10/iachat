class Captain::ContactMemories::HardDeleteExpiredJob < ApplicationJob
  queue_as :scheduled_jobs

  RETENTION_DAYS = 30

  def perform
    count = Captain::ContactMemory.where('deleted_at < ?', RETENTION_DAYS.days.ago).delete_all
    Rails.logger.info("[ContactMemory::HardDeleteExpiredJob] hard-deleted #{count} records")
  end
end
