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
end
# rubocop:enable RSpec/SpecFilePathFormat
