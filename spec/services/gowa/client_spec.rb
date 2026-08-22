require 'rails_helper'

RSpec.describe Gowa::Client do
  let(:base_url) { 'https://gowa.example.test' }
  let(:username) { 'operador' }
  let(:password) { 'senha-segura' }
  let(:client) { described_class.new(base_url, username, password) }

  describe '#create_device' do
    it 'cria um slot com autenticação básica' do
      request = stub_request(:post, "#{base_url}/devices")
                .with(basic_auth: [username, password], body: { device_id: 'chatwoot-1-5561999999999' })
                .to_return(status: 200, body: { results: { id: 'chatwoot-1-5561999999999' } }.to_json)

      expect(client.create_device('chatwoot-1-5561999999999')).to include('results')
      expect(request).to have_been_requested
    end
  end

  describe '#start_login' do
    it 'pede o QR Code do slot criado' do
      request = stub_request(:get, "#{base_url}/devices/chatwoot-1/login")
                .with(basic_auth: [username, password])
                .to_return(status: 200, body: { results: { qr_link: "#{base_url}/statics/qr.png" } }.to_json)

      expect(client.start_login('chatwoot-1').dig('results', 'qr_link')).to eq("#{base_url}/statics/qr.png")
      expect(request).to have_been_requested
    end
  end

  describe '#update_webhook' do
    it 'configura um webhook por dispositivo, assinado e limitado a mensagens' do
      request = stub_request(:patch, "#{base_url}/devices/chatwoot-1/webhook")
                .with(
                  basic_auth: [username, password],
                  body: {
                    webhook_url: 'https://iachat.example.test/webhooks/gowa/9',
                    webhook_secret: 'segredo',
                    webhook_events: 'message'
                  }
                )
                .to_return(status: 200, body: { results: {} }.to_json)

      client.update_webhook('chatwoot-1', 'https://iachat.example.test/webhooks/gowa/9', 'segredo')

      expect(request).to have_been_requested
    end
  end

  describe '#download_media' do
    it 'baixa QR e mídia usando a mesma autenticação básica' do
      request = stub_request(:get, "#{base_url}/statics/media/arquivo.jpeg")
                .with(basic_auth: [username, password])
                .to_return(status: 200, body: 'imagem', headers: { 'Content-Type' => 'image/jpeg' })

      media = client.download_media('/statics/media/arquivo.jpeg')

      expect(media).to eq(body: 'imagem', content_type: 'image/jpeg')
      expect(request).to have_been_requested
    end
  end
end
