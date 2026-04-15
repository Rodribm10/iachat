# frozen_string_literal: true

class Captain::Lifecycle::Guards::MinInterval < Captain::Lifecycle::Guards::Base
  MAX_DELAY = 2.hours

  def check
    config = Captain::Lifecycle::Config.for_account(@account)
    interval = config.min_interval_minutes.to_i
    return pass if interval <= 0

    last_sent_at = last_sent_delivery_at
    return pass if last_sent_at.blank?

    earliest_allowed = last_sent_at + interval.minutes
    return pass if @delivery.fire_at >= earliest_allowed

    delay = earliest_allowed - @delivery.fire_at
    return skip('too_stale') if delay > MAX_DELAY

    reschedule(earliest_allowed)
  end

  private

  def last_sent_delivery_at
    Captain::Lifecycle::Delivery
      .where(captain_reservation_id: @reservation.id,
             status: 'sent',
             origin: 'scheduled_lifecycle')
      .maximum(:sent_at)
  end
end
