# frozen_string_literal: true

class Captain::Lifecycle::DispatcherJob < ApplicationJob
  queue_as :default

  def self.perform_at(fire_at, delivery_id)
    set(wait_until: fire_at).perform_later(delivery_id)
  end

  def perform(delivery_id)
    # Stub — full implementation lands in Task 16.
  end
end
