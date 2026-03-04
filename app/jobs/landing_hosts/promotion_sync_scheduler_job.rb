class LandingHosts::PromotionSyncSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    LandingHost.find_each(&:sync_promotion_to_faq)
  end
end
