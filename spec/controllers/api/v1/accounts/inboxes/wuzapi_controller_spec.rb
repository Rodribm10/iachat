require 'rails_helper'

RSpec.describe 'Wuzapi Inbox API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:wuzapi_client) { instance_double(Wuzapi::Client) }

  let!(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'wuzapi',
      phone_number: '+5511999999999',
      provider_config: {
        'wuzapi_base_url' => 'https://wuzapi.example.com',
        'auto_create_user' => false
      },
      wuzapi_user_token: 'user-token',
      wuzapi_admin_token: 'admin-token',
      validate_provider_config: false,
      sync_templates: false
    )
  end
  let(:inbox) { channel.inbox }
  let(:headers) { admin.create_new_auth_token }
  let(:expected_webhook_url) { inbox.callback_webhook_url.to_s.sub('/webhooks/whatsapp/+', '/webhooks/whatsapp/') }

  before do
    allow(channel).to receive(:setup_webhooks)
    allow(Wuzapi::Client).to receive(:new).and_return(wuzapi_client)
  end

  describe 'POST /api/v1/accounts/:account_id/inboxes/:inbox_id/wuzapi/connect' do
    it 'configures webhook before connecting the session' do
      allow(wuzapi_client).to receive(:set_webhook).and_return({ 'success' => true })
      allow(wuzapi_client).to receive(:session_connect).and_return({ 'success' => true })

      post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/wuzapi/connect", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(wuzapi_client).to have_received(:set_webhook).with('user-token', expected_webhook_url)
      expect(wuzapi_client).to have_received(:session_connect).with('user-token')
    end
  end

  describe 'PUT /api/v1/accounts/:account_id/inboxes/:inbox_id/wuzapi/update_webhook' do
    it 'updates webhook using inbox callback url' do
      allow(wuzapi_client).to receive(:update_webhook).and_return({ 'success' => true })

      put "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/wuzapi/update_webhook", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(wuzapi_client).to have_received(:update_webhook).with('user-token', expected_webhook_url)
    end
  end
end
