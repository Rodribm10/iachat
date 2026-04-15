FactoryBot.define do
  factory :captain_unit, class: 'Captain::Unit' do
    association :account
    sequence(:name) { |n| "Unidade #{n}" }
    inter_pix_key { SecureRandom.uuid }
    inter_account_number { Faker::Number.number(digits: 8) }

    brand do
      Captain::Brand.find_by(account_id: account.id) || association(:captain_brand, account: account)
    end
  end
end
