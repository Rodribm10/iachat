FactoryBot.define do
  factory :captain_brand, class: 'Captain::Brand' do
    association :account
    sequence(:name) { |n| "Brand #{n}" }
  end
end
