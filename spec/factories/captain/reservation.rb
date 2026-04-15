# frozen_string_literal: true

FactoryBot.define do
  factory :captain_reservation, class: 'Captain::Reservation' do
    association :account
    association :inbox
    association :contact
    association :contact_inbox

    suite_identifier { 'Suite 101' }
    check_in_at { 1.day.from_now.beginning_of_hour }
    check_out_at { 2.days.from_now.beginning_of_hour }
    status { :confirmed }
    total_amount { 300.00 }
    metadata { {} }

    unit { nil }
  end
end
