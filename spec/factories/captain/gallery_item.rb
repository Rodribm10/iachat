FactoryBot.define do
  factory :captain_gallery_item, class: 'Captain::GalleryItem' do
    account
    captain_unit do
      brand = create(:captain_brand, account: account)
      Captain::Unit.create!(
        account: account,
        brand: brand,
        name: "Unidade Factory #{SecureRandom.hex(4)}",
        inter_pix_key: SecureRandom.uuid,
        inter_account_number: Faker::Number.number(digits: 8)
      )
    end
    created_by { create(:user, account: account) }
    scope { 'global' }
    suite_category { 'hidromassagem' }
    suite_number { '101' }
    description { 'Foto da suíte com hidromassagem' }
    active { true }

    trait :inbox_scoped do
      scope { 'inbox' }
    end

    after(:build) do |item|
      item.inbox = item.captain_unit&.inbox || create(:inbox, account: item.account) if item.scope == 'inbox' && item.inbox.blank?

      next if item.image.attached?

      item.image.attach(
        io: File.open(Rails.root.join('spec/assets/sample.png')),
        filename: 'sample.png',
        content_type: 'image/png'
      )
    end
  end
end
