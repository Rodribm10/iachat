require 'rails_helper'

RSpec.describe 'GOWA Inbox API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:gowa_client) { instance_double(Gowa::Client) }
  let(:headers) { admin.create_new_auth_token }

  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'gowa',
      phone_number: '+5511999999999',
      provider_config: {
        'gowa_base_url' => 'https://gowa.example.com',
        'gowa_device_id' => 'Academia-DomBosco',
        'webhook_secret' => 'segredo-webhook'
      },
      gowa_username: 'operador',
      gowa_password: 'senha',
      validate_provider_config: false,
      sync_templates: false
    )
  end
  let(:inbox) { channel.inbox }

  before do
    allow(Gowa::Client).to receive(:new).and_return(gowa_client)
    allow(gowa_client).to receive(:update_webhook).and_return({ 'results' => {} })
  end

  describe 'GET /api/v1/accounts/:account_id/inboxes/:inbox_id/gowa/qr' do
    it 'returns a fresh non-cacheable QR Code with its expiration' do
      allow(gowa_client).to receive(:start_login).with('Academia-DomBosco').and_return(
        'results' => {
          'qr_link' => 'https://gowa.example.com/statics/qr.png',
          'qr_duration' => 30
        }
      )
      allow(gowa_client).to receive(:download_media)
        .with('https://gowa.example.com/statics/qr.png')
        .and_return(body: 'imagem-do-qr', content_type: 'image/png')

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/gowa/qr", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.parsed_body).to include(
        'qrcode' => "data:image/png;base64,#{Base64.strict_encode64('imagem-do-qr')}",
        'expires_in' => 30
      )
      expect(response.parsed_body['generated_at']).to be_present
    end
  end
end
