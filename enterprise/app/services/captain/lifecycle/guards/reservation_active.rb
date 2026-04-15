# frozen_string_literal: true

class Captain::Lifecycle::Guards::ReservationActive < Captain::Lifecycle::Guards::Base
  BLOCKING_STATUSES = %w[cancelled no_show].freeze

  def check
    return skip('reservation_cancelled') if BLOCKING_STATUSES.include?(@reservation.status.to_s)

    pass
  end
end
