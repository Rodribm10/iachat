# frozen_string_literal: true

class Captain::Lifecycle::EventResolver
  UNSUPPORTED_IN_MVP = %w[checkin.detected checkout.detected].freeze

  def self.resolve(reservation, event_name)
    return nil if UNSUPPORTED_IN_MVP.include?(event_name)

    case event_name
    when 'reservation.confirmed'
      reservation.updated_at
    when 'checkin.scheduled_at'
      reservation.check_in_at
    when 'checkout.scheduled_at'
      reservation.check_out_at
    when 'reservation.cancelled'
      reservation.updated_at if reservation.status.to_s == 'cancelled'
    when 'reservation.no_show'
      reservation.check_in_at&.+(1.hour)
    else
      raise ArgumentError, "unknown event: #{event_name.inspect}"
    end
  end
end
