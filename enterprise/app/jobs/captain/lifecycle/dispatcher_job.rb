# frozen_string_literal: true

class Captain::Lifecycle::DispatcherJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def self.perform_at(fire_at, delivery_id)
    set(wait_until: fire_at).perform_later(delivery_id)
  end

  def perform(delivery_id)
    delivery = Captain::Lifecycle::Delivery.find_by(id: delivery_id)
    return if delivery.blank?

    Captain::Lifecycle::Dispatcher.new(delivery).call
  end
end
