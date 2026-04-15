require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::LifecycleDeliveries', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:unit) { create(:captain_unit, account: account) }
  let(:reservation) { create(:captain_reservation, account: account, unit: unit) }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/lifecycle_deliveries' do
    before do
      allow(Captain::Lifecycle::Scheduler).to receive(:schedule_for)
    end

    it 'returns deliveries of the account, paginated' do
      create_list(:captain_lifecycle_delivery, 3, account: account, captain_reservation: reservation)
      get "/api/v1/accounts/#{account.id}/captain/lifecycle_deliveries",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response[:payload].length).to eq(3)
      expect(json_response[:meta][:total_count]).to eq(3)
    end

    it 'filters by status' do
      create(:captain_lifecycle_delivery, account: account, captain_reservation: reservation, status: 'sent', sent_at: Time.current)
      create(:captain_lifecycle_delivery, account: account, captain_reservation: reservation, status: 'skipped', skip_reason: 'quiet_hours')

      get "/api/v1/accounts/#{account.id}/captain/lifecycle_deliveries?status=skipped",
          headers: admin.create_new_auth_token, as: :json

      expect(json_response[:payload].length).to eq(1)
      expect(json_response[:payload].first[:status]).to eq('skipped')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/captain/lifecycle_deliveries/:id' do
    before { allow(Captain::Lifecycle::Scheduler).to receive(:schedule_for) }

    it 'returns the rendered_body' do
      delivery = create(:captain_lifecycle_delivery,
                        account: account,
                        captain_reservation: reservation,
                        rendered_body: 'Oi João!')
      get "/api/v1/accounts/#{account.id}/captain/lifecycle_deliveries/#{delivery.id}",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(json_response[:rendered_body]).to eq('Oi João!')
    end
  end
end
