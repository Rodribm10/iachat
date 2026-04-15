# frozen_string_literal: true

class Captain::Lifecycle::Scheduler
  CHECKIN_EVENTS = %w[checkin.scheduled_at checkin.detected].freeze

  class << self
    def schedule_for(reservation)
      rules = Captain::Lifecycle::Rule
              .where(account_id: reservation.account_id)
              .active
      rules.each { |rule| schedule_one_rule(reservation, rule) }
    end

    def cancel_pending(reservation)
      Captain::Lifecycle::Delivery
        .where(captain_reservation_id: reservation.id, status: 'scheduled')
        .update_all(status: 'cancelled', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end

    def reschedule_for_checkin_change(reservation)
      Captain::Lifecycle::Delivery
        .where(captain_reservation_id: reservation.id, status: 'scheduled')
        .joins('INNER JOIN captain_lifecycle_rules ON captain_lifecycle_rules.id = captain_lifecycle_deliveries.lifecycle_rule_id')
        .where(captain_lifecycle_rules: { event: CHECKIN_EVENTS })
        .update_all(status: 'cancelled', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      Captain::Lifecycle::Rule
        .where(account_id: reservation.account_id, event: CHECKIN_EVENTS)
        .active
        .each { |rule| schedule_one_rule(reservation, rule) }
    end

    private

    def schedule_one_rule(reservation, rule)
      return unless rule.matches_reservation?(reservation)

      fire_at = compute_fire_at(reservation, rule)
      return if fire_at.nil? || fire_at <= Time.current

      delivery = Captain::Lifecycle::Delivery.create!(
        account_id: reservation.account_id,
        lifecycle_rule_id: rule.id,
        captain_reservation_id: reservation.id,
        inbox_id: reservation.unit&.concierge_inbox_id,
        fire_at: fire_at,
        status: 'scheduled',
        origin: 'scheduled_lifecycle'
      )
      Captain::Lifecycle::DispatcherJob.perform_at(fire_at, delivery.id)
    end

    def compute_fire_at(reservation, rule)
      event_time = Captain::Lifecycle::EventResolver.resolve(reservation, rule.event)
      return nil if event_time.nil?

      event_time + rule.offset_minutes.minutes
    end
  end
end
