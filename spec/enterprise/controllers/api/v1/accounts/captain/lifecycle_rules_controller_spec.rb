require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::LifecycleRules', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/lifecycle_rules' do
    it 'returns 401 when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/captain/lifecycle_rules"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the account rules (and not others)' do
      create_list(:captain_lifecycle_rule, 2, account: account)
      create(:captain_lifecycle_rule, account: other_account)

      get "/api/v1/accounts/#{account.id}/captain/lifecycle_rules",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response[:payload].length).to eq(2)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/captain/lifecycle_rules' do
    let(:valid_params) do
      {
        rule: {
          name: 'Lembrete pré check-in',
          event: 'checkin.scheduled_at',
          offset_minutes: -10,
          message_type: 'text',
          message_body: 'Oi {{ customer.first_name }}',
          filters: { unit_ids: [1] },
          enabled: true
        }
      }
    end

    it 'blocks agents' do
      post "/api/v1/accounts/#{account.id}/captain/lifecycle_rules",
           params: valid_params, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'creates for admin' do
      post "/api/v1/accounts/#{account.id}/captain/lifecycle_rules",
           params: valid_params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(json_response[:name]).to eq('Lembrete pré check-in')
      expect(Captain::Lifecycle::Rule.where(account: account).count).to eq(1)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/captain/lifecycle_rules/:id' do
    let(:rule) { create(:captain_lifecycle_rule, account: account, name: 'old') }

    it 'updates for admin' do
      patch "/api/v1/accounts/#{account.id}/captain/lifecycle_rules/#{rule.id}",
            params: { rule: { name: 'new' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(rule.reload.name).to eq('new')
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/captain/lifecycle_rules/:id' do
    it 'destroys for admin' do
      rule = create(:captain_lifecycle_rule, account: account)
      delete "/api/v1/accounts/#{account.id}/captain/lifecycle_rules/#{rule.id}",
             headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(Captain::Lifecycle::Rule.where(id: rule.id)).to be_empty
    end
  end
end
