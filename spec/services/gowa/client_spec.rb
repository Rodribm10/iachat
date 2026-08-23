require 'rails_helper'

RSpec.describe Gowa::Client do
  let(:base_url) { 'https://gowa.example.test' }
  let(:username) { 'operador' }
  let(:password) { 'senha-segura' }
  let(:client) { described_class.new(base_url, username, password) }

  describe '#send_attachment' do
    # 23/08/2026: arte de 1,8 MB da academia. O GOWA aceitava o upload e depois
    # devolvia 500 "context deadline exceeded" ao repassar pro CDN do WhatsApp —
    # a foto nunca chegava. A mesma imagem em ~160 KB sobe sem drama.
    def build_attachment(byte_size:, content_type: 'image/png', filename: 'arte.png')
      blob = instance_double(
        ActiveStorage::Blob,
        id: 1,
        byte_size: byte_size,
        content_type: content_type,
        filename: filename,
        download: 'bytes-originais'
      )
      file = double(blob: blob) # rubocop:disable RSpec/VerifiedDoubles
      instance_double(Attachment, file: file)
    end

    it 'recomprime a imagem grande antes de subir pro GOWA' do
      attachment = build_attachment(byte_size: 1_800_000)
      compressed = Tempfile.new(['out', '.jpg'], binmode: true)
      compressed.write('bytes-comprimidos')
      compressed.flush
      allow(client).to receive(:downscale).and_return(compressed)

      request = stub_request(:post, "#{base_url}/send/image")
                .with { |req| req.body.include?('arte.jpg') && req.body.include?('bytes-comprimidos') }
                .to_return(status: 200, body: { results: { message_id: 'ABC' } }.to_json)

      client.send_attachment('Device-1', '5561999999999', attachment, caption: 'oi')

      expect(request).to have_been_requested
    end

    it 'mantém o arquivo original quando a imagem já é pequena' do
      attachment = build_attachment(byte_size: 90_000)
      allow(attachment.file.blob).to receive(:open).and_yield(StringIO.new('bytes-originais'))
      expect(client).not_to receive(:downscale)

      request = stub_request(:post, "#{base_url}/send/image")
                .with { |req| req.body.include?('arte.png') }
                .to_return(status: 200, body: { results: { message_id: 'ABC' } }.to_json)

      client.send_attachment('Device-1', '5561999999999', attachment)

      expect(request).to have_been_requested
    end
  end

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
