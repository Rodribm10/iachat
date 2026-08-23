require 'rails_helper'

RSpec.describe 'Webhooks::Captain::TypingController', type: :request do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'gowa',
      provider_config: {
        'gowa_base_url' => 'https://gowa.example',
        'gowa_device_id' => 'Device-1',
        'gowa_username' => 'user',
        'gowa_password' => 'pass'
      },
      validate_provider_config: false,
      sync_templates: false
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5561999999999') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:provider_service) { instance_double(Whatsapp::Providers::GowaService, toggle_typing_status: true) }

  before do
    allow(Captain::Hermes).to receive(:callback_signing_secret).and_return(nil)
    allow(Whatsapp::Providers::GowaService).to receive(:new).and_return(provider_service)
  end

  it 'liga o digitando no canal da conversa' do
    post '/webhooks/captain/typing',
         params: { inbox_id: inbox.id, conversation_internal_id: conversation.id, typing_status: 'on' }

    expect(response).to have_http_status(:ok)
    expect(provider_service).to have_received(:toggle_typing_status)
      .with(Events::Types::CONVERSATION_TYPING_ON, hash_including(recipient_id: '+5561999999999'))
  end

  it 'desliga o digitando quando o status é off' do
    post '/webhooks/captain/typing',
         params: { inbox_id: inbox.id, conversation_internal_id: conversation.id, typing_status: 'off' }

    expect(response).to have_http_status(:ok)
    expect(provider_service).to have_received(:toggle_typing_status)
      .with(Events::Types::CONVERSATION_TYPING_OFF, any_args)
  end

  it 'devolve 404 quando a conversa não existe na inbox' do
    post '/webhooks/captain/typing',
         params: { inbox_id: inbox.id, conversation_internal_id: 0, typing_status: 'on' }

    expect(response).to have_http_status(:not_found)
  end
end
