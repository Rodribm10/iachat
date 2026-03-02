class Captain::Notifications::NotificationScannerJob < ApplicationJob
  queue_as :scheduled_jobs

  # Tolerance window around the target time (job runs every 5 min, so ±5 min ensures coverage)
  WINDOW_MINUTES = 5

  def perform
    Captain::NotificationTemplate.active.find_each do |template|
      eligible_reservations_for(template).find_each do |reservation|
        Captain::Notifications::SendNotificationService.new(reservation, template).perform
      end
    end
  end

  private

  def eligible_reservations_for(template)
    target_time = compute_target_time(template)
    window_start = target_time - WINDOW_MINUTES.minutes
    window_end   = target_time + WINDOW_MINUTES.minutes

    Captain::Reservation
      .joins(:conversation)
      .where(conversations: { inbox_id: template.inbox_id })
      .where(status: Captain::Reservation.statuses.slice(:confirmed, :active).values)
      .where(check_in_at: window_start..window_end)
      .where.not(conversation_id: nil)
      .where(
        "NOT (captain_reservations.metadata->'notified_templates' @> ?::jsonb)",
        "[#{template.id}]"
      )
  end

  def compute_target_time(template)
    if template.before?
      template.timing_minutes.minutes.from_now
    else
      template.timing_minutes.minutes.ago
    end
  end
end
