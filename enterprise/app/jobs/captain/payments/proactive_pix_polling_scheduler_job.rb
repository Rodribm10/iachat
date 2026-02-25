class Captain::Payments::ProactivePixPollingSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_SCAN_AGE = 2.hours

  def perform
    eligible_scope.in_batches(of: 100) do |batch|
      batch.pluck(:id).each do |charge_id|
        Captain::Payments::PollPixChargeStatusJob.perform_later(charge_id)
      end
    end
  end

  private

  def eligible_scope
    Captain::PixCharge
      .joins(:reservation, :unit)
      .where(status: 'active')
      .where(captain_reservations: {
               status: Captain::Reservation.statuses[:pending_payment],
               payment_status: 'pending'
             })
      .where(captain_units: { proactive_pix_polling_enabled: true })
      .where('captain_pix_charges.created_at >= ?', MAX_SCAN_AGE.ago)
      .order(:id)
  end
end
