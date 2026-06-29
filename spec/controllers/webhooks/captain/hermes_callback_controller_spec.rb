require 'rails_helper'

RSpec.describe 'Webhooks::Captain::HermesCallbackController', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: :pending,
      updated_at: Time.current
    )
  end

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    create(
      :message,
      conversation: conversation,
      account: account,
      inbox: inbox,
      message_type: :incoming,
      content: 'posso levar animais para o hotel ?'
    )

    allow(Captain::Hermes).to receive(:callback_signing_secret).and_return(nil)
    allow(Captain::Hermes::DelayedReplyJob).to receive(:perform_later)
  end

  describe 'POST /webhooks/captain/hermes_callback' do
    it 'marca triagem humana com nota interna de motivo real quando Hermes pede verificacao humana' do
      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'um momento - vou verificar ....' }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).to include('triagem_humana')

      note = conversation.messages.where(private: true).last
      expect(note.content).to include('Motivo: a IA não tinha resposta segura para a última pergunta')
      expect(note.content).to include('Última mensagem do cliente: "posso levar animais para o hotel ?"')
      expect(note.content).not_to include('handoff_intencional')
      expect(note.content_attributes).to include('external_source' => 'hermes_human_triage', 'triage_reason' => 'sem_resposta_segura')
    end

    it 'nao duplica a nota quando a conversa ja esta em triagem humana' do
      conversation.update_labels(%w[triagem_humana])

      expect do
        post '/webhooks/captain/hermes_callback',
             params: { inbox_id: inbox.id, content: 'um momento - vou verificar ....' }
      end.not_to(change { conversation.messages.where(private: true).count })
    end
  end
end
