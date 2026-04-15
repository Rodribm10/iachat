# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wuzapi::Client do
  let(:base_url) { 'https://wuzapi.test' }
  let(:client) { described_class.new(base_url) }
  let(:user_token) { 'tok' }
  let(:phone) { '5561999999999' }

  describe '#send_buttons' do
    it 'POSTs to /chat/sendbuttons with buttons payload' do
      stub = stub_request(:post, "#{base_url}/chat/sendbuttons")
             .with(
               headers: { 'Token' => user_token },
               body: hash_including(
                 Phone: phone,
                 Text: 'Curtiu?',
                 Buttons: [
                   { DisplayText: 'Sim' },
                   { DisplayText: 'Não' }
                 ]
               )
             )
             .to_return(status: 200, body: { Id: 'msg-1' }.to_json, headers: { 'Content-Type' => 'application/json' })

      response = client.send_buttons(
        user_token, phone, 'Curtiu?',
        [{ text: 'Sim' }, { text: 'Não' }]
      )
      expect(response).to be_a(Hash)
      expect(stub).to have_been_requested
    end
  end

  describe '#send_list' do
    it 'POSTs to /chat/sendlist with sections' do
      stub = stub_request(:post, "#{base_url}/chat/sendlist")
             .with(headers: { 'Token' => user_token })
             .to_return(status: 200, body: { Id: 'msg-2' }.to_json, headers: { 'Content-Type' => 'application/json' })

      response = client.send_list(
        user_token, phone,
        text: 'Cardápio',
        button_text: 'Ver opções',
        sections: [{ title: 'Bebidas', rows: [{ title: 'Água', row_id: 'agua' }] }]
      )
      expect(response).to be_a(Hash)
      expect(stub).to have_been_requested
    end
  end

  describe '#send_url_button' do
    it 'POSTs to /chat/sendbuttons with URL button' do
      stub = stub_request(:post, "#{base_url}/chat/sendbuttons")
             .with(body: hash_including('Buttons' => array_including(hash_including('Type' => 'url'))))
             .to_return(status: 200, body: { Id: 'msg-3' }.to_json, headers: { 'Content-Type' => 'application/json' })

      response = client.send_url_button(user_token, phone,
                                        text: 'Avalie no Google',
                                        button_text: 'Avaliar',
                                        url: 'https://g.page/r/XYZ')
      expect(response).to be_a(Hash)
      expect(stub).to have_been_requested
    end
  end
end
