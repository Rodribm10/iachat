FactoryBot.define do
  factory :captain_lifecycle_delivery, class: 'Captain::Lifecycle::Delivery' do
    account
    lifecycle_rule { association :captain_lifecycle_rule, account: account }
    captain_reservation { association :captain_reservation, account: account }
    fire_at { 1.hour.from_now }
    status { 'scheduled' }
    origin { 'scheduled_lifecycle' }
  end
end
