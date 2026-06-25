require 'rails_helper'

RSpec.describe Captain::Hermes::AutoReactService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:assistant) { create(:captain_assistant, account: account) }
  let!(:captain_inbox) { create(:captain_inbox, inbox: inbox, captain_assistant: assistant) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }

  def incoming(content)
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, content: content, source_id: SecureRandom.uuid)
  end

  it 'does not react with affectionate emoji to farewell' do
    message = incoming('tchau, obrigado')

    described_class.maybe_react!(message)

    reaction = conversation.messages.where("content_attributes ->> 'external_source' = ?", 'hermes_auto_react').last
    expect(reaction&.content).to eq('🙏')
  end

  it 'does not react to reservation or price context' do
    message = incoming('Qual o valor da suíte com hidro hoje?')

    expect do
      described_class.maybe_react!(message)
    end.not_to change { conversation.messages.where("content_attributes ->> 'external_source' = ?", 'hermes_auto_react').count }
  end

  it 'does not react to operational guest requests' do
    message = incoming('Pode subir o café aqui no quarto 110?')

    expect do
      described_class.maybe_react!(message)
    end.not_to change { conversation.messages.where("content_attributes ->> 'external_source' = ?", 'hermes_auto_react').count }
  end

  it 'does not react to emoji-only customer message' do
    message = incoming('❤️')

    expect do
      described_class.maybe_react!(message)
    end.not_to change { conversation.messages.where("content_attributes ->> 'external_source' = ?", 'hermes_auto_react').count }
  end

  it 'allows neutral confirmation reaction' do
    message = incoming('ok')

    described_class.maybe_react!(message)

    reaction = conversation.messages.where("content_attributes ->> 'external_source' = ?", 'hermes_auto_react').last
    expect(reaction&.content).to eq('👍')
  end
end
