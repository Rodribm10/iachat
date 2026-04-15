# frozen_string_literal: true

FactoryBot.define do
  factory :captain_lifecycle_rule, class: 'Captain::Lifecycle::Rule' do
    account
    sequence(:name) { |n| "Rule ##{n}" }
    enabled { true }
    event { 'checkin.scheduled_at' }
    offset_minutes { -10 }
    filters { {} }
    message_type { 'text' }
    message_body { 'Olá {{ customer.first_name }}, sua suíte {{ reservation.suite }} está pronta!' }
    priority { 50 }
  end
end
