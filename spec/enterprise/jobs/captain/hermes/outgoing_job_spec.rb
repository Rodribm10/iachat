require 'rails_helper'

RSpec.describe Captain::Hermes::OutgoingJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) do
    create(
      :captain_assistant,
      account: account,
      engine: 'hermes',
      hermes_profile_name: 'juliana_qnn1',
      hermes_webhook_base_url: 'http://hermes.test'
    )
  end
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:message) do
    create(
      :message,
      conversation: conversation,
      account: account,
      inbox: inbox,
      message_type: :incoming,
      content: 'Pode me mandar a localização?'
    )
  end

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    allow(Captain::Hermes::AutoReactService).to receive(:maybe_react!)
    allow(Captain::Hermes::DelayedReplyJob).to receive(:perform_later)
  end

  it 'responde fato conhecido sem despachar a pergunta para o Hermes' do
    client = instance_double(Captain::Hermes::Client)
    allow(Captain::Hermes::Client).to receive(:new).and_return(client)
    expect(client).not_to receive(:dispatch)
    expect(Captain::Hermes::DelayedReplyJob).to receive(:perform_later).with(
      conversation.id,
      a_string_including('https://maps.app.goo.gl/bogrUpmGoiDhUgeR8'),
      'hermes_known_fact_location'
    )

    described_class.perform_now(conversation.id, message.id)
  end
end
