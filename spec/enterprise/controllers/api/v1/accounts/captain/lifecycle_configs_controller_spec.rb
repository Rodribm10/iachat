# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::LifecycleConfigs', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/lifecycle_config' do
    it 'creates a default config on first access' do
      get "/api/v1/accounts/#{account.id}/captain/lifecycle_config",
          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(json_response[:quiet_hours_enabled]).to be(false)
      expect(json_response[:min_interval_minutes]).to eq(30)
      expect(json_response[:max_per_reservation]).to eq(5)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/captain/lifecycle_config' do
    it 'blocks agents' do
      patch "/api/v1/accounts/#{account.id}/captain/lifecycle_config",
            params: { config: { quiet_hours_enabled: true } },
            headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'updates for admin' do
      patch "/api/v1/accounts/#{account.id}/captain/lifecycle_config",
            params: { config: { quiet_hours_enabled: true, quiet_hours_from: '22:00', min_interval_minutes: 60 } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(json_response[:quiet_hours_enabled]).to be(true)
      expect(json_response[:min_interval_minutes]).to eq(60)
    end
  end
end
