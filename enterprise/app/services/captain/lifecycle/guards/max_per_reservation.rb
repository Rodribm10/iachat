# frozen_string_literal: true

class Captain::Lifecycle::Guards::MaxPerReservation < Captain::Lifecycle::Guards::Base
  CAP = 5

  def check
    count = Captain::Lifecycle::Delivery.count_sent_for_reservation(@reservation.id)
    return skip('max_reached') if count >= CAP

    pass
  end
end
