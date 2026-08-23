require 'rails_helper'

RSpec.describe Captain::Hermes::Client do
  describe '#build_payload' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, name: 'Cliente Teste') }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) do
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    end
    let(:client) { described_class.new(inbox) }

    it 'includes quoted WhatsApp message context in the Hermes-visible message' do
      quoted_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: 'A suite Alexa esta disponivel por R$ 199.',
        source_id: 'wamid.quoted-message'
      )
      reply = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        content: 'Pode reservar essa',
        source_id: 'wamid.reply-message',
        content_attributes: { in_reply_to_external_id: quoted_message.source_id }
      )

      payload = client.send(:build_payload, message: reply, conversation: conversation)

      expect(payload[:reply_context]).to include(
        external_id: quoted_message.source_id,
        found: true
      )
      expect(payload[:reply_context][:quoted_message]).to include(
        id: quoted_message.id,
        message_type: 'outgoing',
        sender_label: 'atendente/Hermes',
        content: 'A suite Alexa esta disponivel por R$ 199.'
      )
      expect(payload[:message]).to include('[CONTEXTO DE RESPOSTA DO WHATSAPP]')
      expect(payload[:message]).to include('A suite Alexa esta disponivel por R$ 199.')
      expect(payload[:message]).to include('[RESPOSTA ATUAL DO CLIENTE]')
      expect(payload[:message]).to include('Pode reservar essa')
    end

    it 'includes quoted context when Chatwoot stores the reply as an internal message id' do
      quoted_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: "Stilo hoje fica assim:\n1h R$ 50\nValor pra ate 2 pessoas.",
        source_id: 'WAID:quoted-stilo'
      )
      reply = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        content: 'Quero uma 1 hora na suite desse valor',
        source_id: 'WAID:reply-stilo',
        in_reply_to_id: quoted_message.id
      )

      payload = client.send(:build_payload, message: reply, conversation: conversation)

      expect(payload[:reply_context]).to include(
        message_id: quoted_message.id,
        external_id: quoted_message.source_id,
        found: true
      )
      expect(payload[:message]).to include('Stilo hoje fica assim')
      expect(payload[:message]).to include('1h R$ 50')
      expect(payload[:message]).to include('resolva a referência usando a mensagem citada')
      expect(payload[:message]).to include('Quero uma 1 hora na suite desse valor')
    end

    it 'keeps the combined incoming text while adding quote context' do
      quoted_message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: 'Temos opcoes com hidro e garagem privativa.',
        source_id: 'wamid.quoted-options'
      )
      reply = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        content: 'Essa',
        content_attributes: { in_reply_to_external_id: quoted_message.source_id }
      )

      payload = client.send(
        :build_payload,
        message: reply,
        conversation: conversation,
        content_override: "Quero ver as suites\nEssa"
      )

      expect(payload[:message]).to include('Temos opcoes com hidro e garagem privativa.')
      expect(payload[:message]).to include("Quero ver as suites\nEssa")
    end

    it 'does not add reply context when the message is not a WhatsApp reply' do
      message = create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :incoming,
        content: 'Oi, tem suite disponivel?'
      )

      payload = client.send(:build_payload, message: message, conversation: conversation)

      expect(payload[:reply_context]).to be_nil
      expect(payload[:message]).to eq('Oi, tem suite disponivel?')
    end
  end

  describe '#usable_first_name' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account, name: 'Inbox') }
    let(:client) { described_class.new(inbox) }

    def conversation_with_contact(contact_name, target_inbox: inbox)
      contact = create(:contact, account: account, name: contact_name)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: target_inbox)
      create(:conversation, account: account, inbox: target_inbox, contact: contact, contact_inbox: contact_inbox)
    end

    it 'returns the first name for a normal person name' do
      conversation = conversation_with_contact('Andreza Caroliny')

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to eq('Andreza')
    end

    it 'does not reject a person name that happens to carry a company-like suffix' do
      conversation = conversation_with_contact('Maurício Informática')

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to eq('Maurício')
    end

    it 'returns a single-word name as is' do
      conversation = conversation_with_contact('Mylena')

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to eq('Mylena')
    end

    it 'rejects a contact saved with the establishment own name (matches the inbox name)' do
      establishment_inbox = create(:inbox, account: account, name: 'Academia Dom Bosco — GoWA')
      establishment_client = described_class.new(establishment_inbox)
      conversation = conversation_with_contact('Academia Dom Bosco', target_inbox: establishment_inbox)

      expect(establishment_client.send(:usable_first_name, conversation.contact, conversation)).to be_nil
    end

    it 'rejects a contact whose name matches the assistant product_name' do
      assistant = create(:captain_assistant, account: account, config: { product_name: 'Studio Fit Pro' })
      create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
      conversation = conversation_with_contact('Studio Fit Pro')

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to be_nil
    end

    it 'rejects an emoji-only name' do
      conversation = conversation_with_contact('😅‼️')

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to be_nil
    end

    it 'rejects a name that is actually a phone number' do
      conversation = conversation_with_contact('556182098580')

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to be_nil
    end

    it 'returns nil when the contact name is nil' do
      conversation = conversation_with_contact(nil)

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to be_nil
    end

    it 'returns nil when the contact name is blank' do
      conversation = conversation_with_contact('')

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to be_nil
    end

    it 'rejects a generic placeholder name' do
      conversation = conversation_with_contact('Unknown')

      expect(client.send(:usable_first_name, conversation.contact, conversation)).to be_nil
    end

    it 'returns nil when there is no contact at all' do
      conversation = conversation_with_contact('Andreza Caroliny')

      expect(client.send(:usable_first_name, nil, conversation)).to be_nil
    end
  end
end
