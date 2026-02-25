FactoryBot.define do
  factory :captain_unit, class: 'Captain::Unit' do
    association :account
    association :brand, factory: :captain_brand, account: account
    sequence(:name) { |n| "Unidade #{n}" }
    inter_pix_key { SecureRandom.uuid }
    inter_account_number { Faker::Number.number(digits: 8) }
  end
end
