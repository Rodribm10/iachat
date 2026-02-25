# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::GalleryItems', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:unit) do
    Captain::Unit.create!(
      account: account,
      brand: brand,
      inbox: inbox,
      name: 'Unidade Teste Galeria',
      inter_pix_key: SecureRandom.uuid,
      inter_account_number: '12345678'
    )
  end

  describe 'POST /api/v1/accounts/:account_id/captain/gallery_items' do
    it 'creates a gallery item with image and metadata' do
      post "/api/v1/accounts/#{account.id}/captain/gallery_items",
           params: {
             captain_gallery_item: {
               scope: 'inbox',
               inbox_id: inbox.id,
               captain_unit_id: unit.id,
               suite_category: 'hidromassagem',
               suite_number: '101',
               description: 'Foto principal da suíte',
               image: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png')
             }
           },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['scope']).to eq('inbox')
      expect(body['inbox_id']).to eq(inbox.id)
      expect(body['captain_unit_id']).to eq(unit.id)
      expect(body['suite_number']).to eq('101')
      expect(body['image_url']).to be_present
    end
  end

  describe 'GET /api/v1/accounts/:account_id/captain/gallery_items' do
    it 'filters by inbox and suite metadata' do
      create(
        :captain_gallery_item,
        :inbox_scoped,
        account: account,
        captain_unit: unit,
        inbox: inbox,
        suite_category: 'hidromassagem',
        suite_number: '101'
      )
      create(
        :captain_gallery_item,
        :inbox_scoped,
        account: account,
        captain_unit: unit,
        inbox: inbox,
        suite_category: 'luxo',
        suite_number: '202'
      )

      get "/api/v1/accounts/#{account.id}/captain/gallery_items",
          params: { scope: 'inbox', inbox_id: inbox.id, suite_category: 'hidromassagem' },
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.size).to eq(1)
      expect(body.first['inbox_id']).to eq(inbox.id)
      expect(body.first['suite_category']).to eq('hidromassagem')
    end
  end
end
