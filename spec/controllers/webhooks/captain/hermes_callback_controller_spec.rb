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

  # Em 25/07/2026 clientes do Instagram receberam — e leram — mensagens como
  # "HTTP 401: Provided authentication token is expired". Erro técnico do Hermes
  # nunca pode virar resposta ao cliente.
  describe 'quando o Hermes devolve erro tecnico no lugar da resposta' do
    erros = [
      'HTTP 401: Provided authentication token is expired. Please try signing in again.',
      '❌ Non-retryable error (HTTP 401): HTTP 401: token expired',
      '🔐 Authentication failed and could not be refreshed — switching to fallback provider...',
      "Traceback (most recent call last):\n  File \"gateway.py\"",
      'NoMethodError: undefined method for nil'
    ]

    erros.each do |erro|
      it "nao entrega ao cliente: #{erro.to_s[0, 42]}" do
        expect(Captain::Hermes::DelayedReplyJob).not_to receive(:perform_later)

        post '/webhooks/captain/hermes_callback', params: { inbox_id: inbox.id, content: erro }

        expect(response).to have_http_status(:ok)
        expect(conversation.reload.messages.where(private: false, message_type: :outgoing)).to be_empty
      end
    end

    it 'registra o erro como nota interna e manda para triagem humana' do
      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'HTTP 401: Provided authentication token is expired.' }

      expect(conversation.reload.label_list).to include('triagem_humana')

      nota = conversation.messages.where(private: true).find do |m|
        m.content_attributes.to_h['external_source'] == 'hermes_error_blocked'
      end
      expect(nota).to be_present
      expect(nota.content).to include('O cliente NÃO recebeu isto')
      expect(nota.content).to include('HTTP 401')
    end

    it 'entrega normalmente uma resposta legitima que apenas menciona a palavra erro' do
      expect(Captain::Hermes::DelayedReplyJob).to receive(:perform_later)

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'Peço desculpas pelo erro na reserva anterior, já corrigimos!' }

      expect(response).to have_http_status(:ok)
    end

    describe 'bloqueio de conteudo interno vazado' do
      # Cada caso é uma família de vazamento que antes só era barrada no motor
      # interno do Captain — o caminho do Hermes deixava passar direto pro cliente.
      {
        'pedaço do system prompt' => '[Contexto] Você é a atendente do 1001 Noites...',
        'identidade do Captain' => 'You are part of Captain, an AI assistant.',
        'narração do que a IA deve fazer' => 'A IA deve sempre confirmar o valor antes de reservar.',
        'instrução condicional vazada' => 'Quando o cliente pedir fotos, envie o catálogo da suíte.',
        'nome técnico de handoff' => 'Vou acionar handoff_to_daniela_reservas para você.',
        'nome interno de cenário' => 'Encaminhando para daniela_reservas agora.',
        'JSON cru' => '{"reasoning": "cliente quer preco", "reply": "R$ 140"}',
        'Liquid não renderizado' => 'Olá {{ contact_name }}, tudo bem?',
        'comando de tool disfarçado' => 'Consulte a ferramenta de disponibilidade antes de responder.'
      }.each do |descricao, payload|
        it "barra #{descricao} e nao entrega ao cliente" do
          expect(Captain::Hermes::DelayedReplyJob).not_to receive(:perform_later)

          post '/webhooks/captain/hermes_callback',
               params: { inbox_id: inbox.id, content: payload }

          expect(response).to have_http_status(:ok)
        end
      end

      it 'registra nota interna com o conteudo barrado e o motivo' do
        post '/webhooks/captain/hermes_callback',
             params: { inbox_id: inbox.id, content: '[Contexto] instrucoes internas da assistente' }

        nota = conversation.reload.messages.where(private: true).find do |m|
          m.content_attributes.to_h['external_source'] == 'hermes_prompt_leak_blocked'
        end
        expect(nota).to be_present
        expect(nota.content).to include('O cliente NÃO recebeu isto')
        expect(nota.content).to include('system_prompt')
      end

      it 'manda a conversa para triagem humana' do
        post '/webhooks/captain/hermes_callback',
             params: { inbox_id: inbox.id, content: 'A IA deve verificar a agenda antes de confirmar.' }

        expect(conversation.reload.label_list).to include('triagem_humana')
      end
    end

    describe 'entrega de resposta legitima' do
      [
        'Boa tarde! A suíte com hidromassagem está R$ 180 para 3 horas.',
        'Claro, posso te ajudar com a reserva. Para quando seria?',
        'Temos duas unidades na avenida. Qual fica melhor pra você?',
        'O cliente anterior elogiou muito essa suíte!'
      ].each do |payload|
        it "entrega normalmente: #{payload[0, 40]}..." do
          expect(Captain::Hermes::DelayedReplyJob).to receive(:perform_later)

          post '/webhooks/captain/hermes_callback',
               params: { inbox_id: inbox.id, content: payload }

          expect(response).to have_http_status(:ok)
        end
      end
    end
  end
end
