require 'rails_helper'

RSpec.describe Captain::Hermes::OutgoingJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  # Depois de 22/08/2026 o Hermes e o unico motor de resposta: um assistant
  # sem config de Hermes nao teria enabled_for? true e o guard nem seria
  # exercitado.
  let(:assistant) do
    create(:captain_assistant, account: account, engine: 'hermes',
                               hermes_profile_name: 'teste', hermes_webhook_base_url: 'http://hermes.local')
  end
  let(:conversation) { create(:conversation, inbox: inbox, account: account, status: :open) }
  let(:client) { instance_double(Captain::Hermes::Client, dispatch: true) }

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    allow(Captain::Hermes::Client).to receive(:new).and_return(client)
  end

  def incoming(content = 'Oi')
    create(:message, conversation: conversation, inbox: inbox, account: account, message_type: :incoming, content: content)
  end

  def run_job
    message = incoming
    described_class.new.perform(conversation.id, message.id)
  end

  it 'despacha normalmente quando a conversa nao esta em triagem humana' do
    run_job

    expect(client).to have_received(:dispatch)
  end

  it 'nao despacha enquanto a conversa esta em triagem humana' do
    Captain::Hermes::HumanTriageService.perform(conversation: conversation, reason: 'sem_resposta_segura')

    run_job

    expect(client).not_to have_received(:dispatch)
  end

  # Regressao central deste fix (conv 126 da conta 2, 25/08/2026): handoff as
  # 14:44 marcou triagem_humana; a conversa foi devolvida (status pending) as
  # 15:00 mas a label nunca saia sozinha e o guard barrava a IA para sempre.
  # A partir de Enterprise::Conversation#release_ai_from_human_triage, a
  # transicao para pending libera as labels e o guard deixa de bloquear.
  it 'volta a despachar depois que a conversa em triagem humana e devolvida para pending' do
    Captain::Hermes::HumanTriageService.perform(conversation: conversation, reason: 'sem_resposta_segura')
    expect(conversation.reload.label_list).to include('triagem_humana')

    conversation.update!(status: :pending)
    expect(conversation.reload.label_list).to be_empty

    run_job

    expect(client).to have_received(:dispatch)
  end
end
