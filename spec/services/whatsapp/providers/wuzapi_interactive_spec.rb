# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe Whatsapp::Providers::WuzapiService, '#send_interactive_message' do
  let(:channel) do
    create(:channel_whatsapp, provider: 'wuzapi', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'wuzapi_base_url' => 'http://localhost:8080' })
  end
  let(:service) { described_class.new(whatsapp_channel: channel) }
  let(:phone) { '+5561999999999' }
  let(:wuzapi_client) { instance_double(Wuzapi::Client) }

  before do
    allow(Wuzapi::Client).to receive(:new).and_return(wuzapi_client)
    allow(channel).to receive(:wuzapi_user_token).and_return('tok')
  end

  describe '#send_interactive_message' do
    it 'dispatches quick_reply buttons' do
      payload = { 'type' => 'quick_reply', 'body' => 'Curtiu?',
                  'buttons' => [{ 'id' => 'yes', 'text' => 'Sim' }] }
      expect(wuzapi_client).to receive(:send_buttons)
        .with('tok', '5561999999999', 'Curtiu?', [{ text: 'Sim' }])
        .and_return({ 'Id' => 'm-1' })

      service.send_interactive_message(phone, payload)
    end

    it 'dispatches url_button' do
      payload = { 'type' => 'url_button', 'body' => 'Avalie',
                  'button' => { 'text' => 'Abrir', 'url' => 'https://g.page/r/1' } }
      expect(wuzapi_client).to receive(:send_url_button)
        .with('tok', '5561999999999', text: 'Avalie', button_text: 'Abrir', url: 'https://g.page/r/1')
        .and_return({ 'Id' => 'm-2' })

      service.send_interactive_message(phone, payload)
    end

    it 'dispatches list' do
      payload = { 'type' => 'list', 'body' => 'Cardápio', 'button_text' => 'Ver',
                  'sections' => [{ 'title' => 'Bebidas', 'rows' => [{ 'title' => 'Água', 'row_id' => 'a1' }] }] }
      expect(wuzapi_client).to receive(:send_list).and_return({ 'Id' => 'm-3' })
      service.send_interactive_message(phone, payload)
    end

    it 'raises for unknown type' do
      expect { service.send_interactive_message(phone, 'type' => 'xyz') }
        .to raise_error(ArgumentError, /unsupported interactive type/)
    end
  end

  describe '#send_message' do
    let(:conversation) { create(:conversation, account: channel.account, inbox: channel.inbox) }
    let(:message) do
      create(:message, message_type: :outgoing, account: channel.account, inbox: channel.inbox,
                       conversation: conversation, content: 'Audio')
    end

    it 'sends audio attachments through the Wuzapi audio endpoint' do
      attachment = message.attachments.new(account_id: message.account_id, file_type: :audio)
      attachment.file.attach(io: Rails.root.join('spec/assets/sample.ogg').open, filename: 'sample.ogg', content_type: 'audio/ogg')
      attachment.save!

      expect(wuzapi_client).to receive(:send_audio)
        .with(
          'tok',
          '5561999999999',
          start_with('data:audio/ogg;base64,'),
          hash_including(mimetype: 'audio/ogg; codecs=opus', ptt: true)
        )
        .and_return({ 'data' => { 'Id' => 'audio-1' } })
      expect(wuzapi_client).not_to receive(:send_file)

      expect(service.send_message(phone, message)).to eq('WAID:audio-1')
    end

    it 'normalizes audio/opus attachments to audio/ogg data URIs' do
      attachment = message.attachments.new(account_id: message.account_id, file_type: :audio)
      attachment.file.attach(io: Rails.root.join('spec/assets/sample.ogg').open, filename: 'sample.ogg', content_type: 'audio/opus')
      attachment.save!

      expect(wuzapi_client).to receive(:send_audio)
        .with(
          'tok',
          '5561999999999',
          start_with('data:audio/ogg;base64,'),
          hash_including(mimetype: 'audio/ogg; codecs=opus', ptt: true)
        )
        .and_return({ 'data' => { 'Id' => 'audio-2' } })

      expect(service.send_message(phone, message)).to eq('WAID:audio-2')
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
