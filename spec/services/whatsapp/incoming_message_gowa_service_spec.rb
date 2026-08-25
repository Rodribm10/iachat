require 'rails_helper'

RSpec.describe Whatsapp::IncomingMessageGowaService do
  let(:account) { create(:account) }
  let(:gowa_client) { instance_double(Gowa::Client) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'gowa',
      phone_number: '+5561999999999',
      gowa_username: 'operador',
      gowa_password: 'senha-segura',
      provider_config: { 'gowa_base_url' => 'https://gowa.example.test' },
      sync_templates: false
    )
  end
  let(:inbox) { channel.inbox }

  before do
    allow(Gowa::Client).to receive(:new).and_return(gowa_client)
    allow(gowa_client).to receive(:create_device).and_return({ 'results' => { 'id' => 'chatwoot-1-5561999999999' } })
    allow(gowa_client).to receive(:device_status).and_return({ 'results' => { 'is_connected' => false } })
    allow(gowa_client).to receive(:update_webhook).and_return({ 'results' => {} })
  end

  it 'cria contato, conversa e mensagem para um webhook de texto' do
    params = {
      'event' => 'message',
      'session_id' => 'chatwoot-1-5561999999999',
      'payload' => {
        'id' => '3EB0ABC',
        'chat_id' => '5561988887777@s.whatsapp.net',
        'from' => '5561988887777@s.whatsapp.net',
        'from_name' => 'Cliente GOWA',
        'timestamp' => '2026-08-21T12:00:00Z',
        'is_from_me' => false,
        'body' => 'Olá, preciso de uma reserva.'
      }
    }

    expect do
      described_class.new(inbox: inbox, params: params).perform
    end.to change(Message, :count).by(1)

    message = inbox.messages.order(:id).last
    expect(message.content).to eq('Olá, preciso de uma reserva.')
    expect(message.source_id).to eq('GOWA:3EB0ABC')
    expect(message.sender.name).to eq('Cliente GOWA')
  end

  it 'ignora mensagens de grupos' do
    params = {
      'event' => 'message',
      'payload' => {
        'id' => '3EB0GRUPO',
        'chat_id' => '120363000000@g.us',
        'from' => '5561988887777@s.whatsapp.net',
        'is_from_me' => false,
        'body' => 'Mensagem de grupo'
      }
    }

    expect do
      described_class.new(inbox: inbox, params: params).perform
    end.not_to change(Message, :count)
  end

  context 'when a mensagem é um eco (is_from_me), ex: a própria conta inicia a conversa pelo celular' do
    let(:echo_params) do
      {
        'event' => 'message',
        'payload' => {
          'id' => '3EB0ECO1',
          'chat_id' => '5561988887777@s.whatsapp.net',
          'from' => '5561999999999@s.whatsapp.net',
          'from_name' => 'Academia Dom Bosco',
          'sender_display_name' => 'Academia Dom Bosco',
          'timestamp' => '2026-08-21T12:05:00Z',
          'is_from_me' => true,
          'body' => 'Olá! Seja bem-vindo à Academia Dom Bosco!'
        }
      }
    end

    it 'cria o contato do cliente sem usar o nome da própria conta, e com o telefone do cliente' do
      expect do
        described_class.new(inbox: inbox, params: echo_params).perform
      end.to change(Message, :count).by(1)

      message = inbox.messages.order(:id).last
      contact = message.conversation.contact

      expect(message.message_type).to eq('outgoing')
      expect(contact.name).not_to eq('Academia Dom Bosco')
      expect(contact.name).to eq('5561988887777')
      expect(contact.phone_number).to eq('+5561988887777')
    end

    it 'não sobrescreve o nome de um contato já existente' do
      existing_contact = create(:contact, account: account, name: 'Maria Cliente', phone_number: '+5561988887777')
      create(:contact_inbox, contact: existing_contact, inbox: inbox, source_id: '5561988887777')

      expect do
        described_class.new(inbox: inbox, params: echo_params).perform
      end.to change(Message, :count).by(1)

      expect(existing_contact.reload.name).to eq('Maria Cliente')
    end
  end
end
