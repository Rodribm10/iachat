# frozen_string_literal: true

class Captain::Lifecycle::Guards::Base
  def initialize(delivery)
    @delivery = delivery
    @reservation = delivery.captain_reservation
    @account = delivery.account
  end

  def check
    raise NotImplementedError
  end

  protected

  def pass
    { action: :pass }
  end

  def skip(reason)
    { action: :skip, reason: reason }
  end

  def reschedule(new_fire_at)
    { action: :reschedule, fire_at: new_fire_at }
  end
end
