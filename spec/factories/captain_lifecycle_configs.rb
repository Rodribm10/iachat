# frozen_string_literal: true

FactoryBot.define do
  factory :captain_lifecycle_config, class: 'Captain::Lifecycle::Config' do
    account
    quiet_hours_enabled { false }
    quiet_hours_from { '23:00' }
    quiet_hours_to { '08:00' }
    min_interval_minutes { 30 }
    pause_on_customer_reply { false }
    pause_on_customer_reply_within_minutes { 60 }
  end
end
