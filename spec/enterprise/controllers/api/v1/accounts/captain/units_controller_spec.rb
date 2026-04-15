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

    it 'creates a default brand automatically when account has no captain brand' do
      account_with_no_brand = create(:account)
      admin_without_brand = create(:user, account: account_with_no_brand, role: :administrator)

      params = {
        captain_unit: {
          name: 'Hotel Sem Marca',
          inter_client_id: 'cid',
          inter_client_secret: 'csecret',
          inter_pix_key: '12345678901',
          inter_account_number: '210339349'
        }
      }

      expect(Captain::Brand.where(account_id: account_with_no_brand.id).count).to eq(0)

      post "/api/v1/accounts/#{account_with_no_brand.id}/captain/units",
           params: params,
           headers: admin_without_brand.create_new_auth_token

      expect(response).to have_http_status(:created)
      brands = Captain::Brand.where(account_id: account_with_no_brand.id)
      expect(brands.count).to eq(1)
      expect(Captain::Unit.last.captain_brand_id).to eq(brands.first.id)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/captain/units/:id/concierge' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:unit) do
      Captain::Unit.create!(
        account: account,
        brand: Captain::Brand.where(account: account).first,
        name: 'Unidade Teste'
      )
    end
    let(:inbox) { create(:inbox, account: account) }

    it 'blocks agents' do
      patch "/api/v1/accounts/#{account.id}/captain/units/#{unit.id}/concierge",
            params: { captain_unit: { concierge_inbox_id: inbox.id } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'updates concierge fields for admin' do
      patch "/api/v1/accounts/#{account.id}/captain/units/#{unit.id}/concierge",
            params: {
              captain_unit: {
                concierge_inbox_id: inbox.id,
                concierge_config: {
                  persona_name: 'Sofia',
                  knowledge: '# Hotel\n',
                  variables: { wifi_password: 'abc123' }
                }
              }
            },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      unit.reload
      expect(unit.concierge_inbox_id).to eq(inbox.id)
      expect(unit.concierge_config['persona_name']).to eq('Sofia')
      expect(unit.concierge_config.dig('variables', 'wifi_password')).to eq('abc123')
    end
  end
end
