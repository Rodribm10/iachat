# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Units', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before do
    Captain::Brand.create!(account: account, name: 'Brand Test')
  end

  describe 'POST /api/v1/accounts/:account_id/captain/units' do
    it 'creates a unit with proactive polling enabled when Inter credentials are complete' do
      params = {
        captain_unit: {
          name: 'Hotel Recanto',
          inter_client_id: 'cid',
          inter_client_secret: 'csecret',
          inter_pix_key: '12345678901',
          inter_account_number: '210339349',
          inter_cert_content: 'cert-content',
          inter_key_content: 'key-content',
          proactive_pix_polling_enabled: true
        }
      }

      post "/api/v1/accounts/#{account.id}/captain/units",
           params: params,
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['proactive_pix_polling_enabled']).to be(true)
      expect(body['has_client_secret']).to be(true)
    end

    it 'rejects enabling proactive polling when Inter credentials are incomplete' do
      params = {
        captain_unit: {
          name: 'Hotel Recanto',
          inter_client_id: 'cid',
          inter_pix_key: '12345678901',
          inter_account_number: '210339349',
          proactive_pix_polling_enabled: true
        }
      }

      post "/api/v1/accounts/#{account.id}/captain/units",
           params: params,
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['errors'].join).to match(/só pode ser habilitado/i)
    end
  end
end
