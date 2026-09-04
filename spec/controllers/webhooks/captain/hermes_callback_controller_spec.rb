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
    # Regressao (conv 18 da academia, 23/08/2026): cliente disse "to em duvida",
    # a IA convidou pra experimental com dia marcado — avanco de venda, nao loop —
    # e a conversa caiu em triagem humana mesmo assim.
    it 'nao trata convite que avanca a venda como repeticao' do
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        message_type: :outgoing,
        content: 'Da pra fazer uma aula experimental gratuita antes de escolher. ' \
                 'Quer que eu veja um horario bom pra voce?',
        content_attributes: { external_source: 'hermes_callback' }
      )

      post '/webhooks/captain/hermes_callback',
           params: {
             inbox_id: inbox.id,
             content: 'Sem problema! Vem fazer uma aula experimental gratuita pra sentir a academia ' \
                      'antes de decidir. Consigo te encaixar na terca ou na quinta?'
           }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).not_to include('triagem_humana')
    end

    it 'ainda escala quando a IA repete a mesma pergunta' do
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        message_type: :outgoing,
        content: 'Perfeito! Qual seu melhor horario pra aula experimental?',
        content_attributes: { external_source: 'hermes_callback' }
      )

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'Qual o melhor horario pra sua aula experimental?' }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).to include('triagem_humana')
    end

    # Regressao (conv 17 da academia, 23/08/2026): o gateway do Hermes reiniciou
    # e o proprio aviso de shutdown foi entregue como resposta no WhatsApp.
    it 'nao entrega aviso de shutdown do gateway ao cliente' do
      aviso = '⚠️ Gateway shutting down — Your current task will be interrupted.'

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: aviso }

      expect(response).to have_http_status(:ok)
      expect(Captain::Hermes::DelayedReplyJob).not_to have_received(:perform_later)
      expect(conversation.reload.messages.where(private: true).map(&:content).join).to include(aviso)
      expect(conversation.reload.label_list).to include('triagem_humana')
    end

    # Regressao (conv 17 da academia, 23/08/2026): o agente respondeu o que sabia
    # e fechou com a ancora numa linha final. Ancorado em \A isso nao casava — o
    # cliente lia "vou verificar", a conversa seguia em pending e ninguem assumia.
    it 'marca triagem humana quando a ancora vem no fim da mensagem, depois da resposta' do
      resposta = "No plano anual da para trancar, e o contrato e estendido pelo mesmo periodo.\n\n" \
                 "Por motivo de saude, precisa apresentar atestado.\n\n" \
                 '⏳ Um momento — vou verificar.'

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: resposta }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).to include('triagem_humana')
      expect(conversation.reload).to be_open
    end

    it 'nao confunde a ancora citada no meio de uma frase com um pedido de transferencia' do
      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'Se eu disser um momento e sumir, me cobra o retorno.' }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).not_to include('triagem_humana')
    end

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

  describe 'quando o Hermes devolve status interno de concorrencia' do
    status_internos = [
      "↪ Redirected current run. I'll adjust using your correction.",
      '⏩ Steered into current run. Your message arrives after the next tool call.',
      "⏳ Queued for the next turn. I'll respond once the current task finishes.",
      "⚡ Interrupting current task. I'll respond to your message shortly.",
      '⏳ Subagent working — your message is queued for when it finishes.',
      '⏳ Compressing context — your message is queued for when it finishes.'
    ]

    status_internos.each do |status_interno|
      it "bloqueia sem entregar ao cliente: #{status_interno[0, 38]}" do
        expect(Captain::Hermes::DelayedReplyJob).not_to receive(:perform_later)

        post '/webhooks/captain/hermes_callback', params: { inbox_id: inbox.id, content: status_interno }

        expect(response).to have_http_status(:ok)
        expect(conversation.reload.messages.where(private: false, message_type: :outgoing)).to be_empty
      end
    end

    it 'registra nota privada sem abrir triagem e permite a resposta final posterior' do
      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: "↪ Redirected current run. I'll adjust using your correction." }

      nota = conversation.reload.messages.where(private: true).find do |mensagem|
        mensagem.content_attributes.to_h['external_source'] == 'hermes_internal_status_blocked'
      end
      expect(nota).to be_present
      expect(nota.content).to include('Status interno do Hermes bloqueado')
      expect(nota.content).to include('Redirected current run')
      expect(conversation.label_list).not_to include('triagem_humana')

      expect(Captain::Hermes::DelayedReplyJob).to receive(:perform_later)
        .with(conversation.id, 'Claro! Para qual data você deseja reservar?')

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'Claro! Para qual data você deseja reservar?' }

      expect(response).to have_http_status(:ok)
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
      'NoMethodError: undefined method for nil',
      'Sorry, I encountered an unexpected error. Try again or use /reset to start a fresh session.'
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

      it 'manda a conversa para triagem humana com o motivo real' do
        post '/webhooks/captain/hermes_callback',
             params: { inbox_id: inbox.id, content: 'A IA deve verificar a agenda antes de confirmar.' }

        conversation.reload
        expect(conversation.label_list).to include('triagem_humana')
        expect(conversation.label_list).to include('triagem_vazamento_prompt')

        nota = conversation.messages.where(private: true).find do |m|
          m.content_attributes.to_h['external_source'] == 'hermes_human_triage'
        end
        expect(nota.content).to include('devolveu conteúdo interno em vez de resposta')
        expect(nota.content_attributes.to_h['triage_reason']).to eq('vazamento_prompt')
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

  # A triagem existe para quando a IA nao sabe responder. Duas respostas
  # parecidas nao provam isso: saudacao responde saudacao. Em 03/09/2026 a
  # conv 126 da academia caiu na triagem duas vezes so por cumprimentar de
  # volta — e a triagem BLOQUEIA a IA nas mensagens seguintes.
  describe 'deteccao de loop' do
    def responde_antes(texto)
      create(
        :message,
        conversation: conversation,
        account: account,
        inbox: inbox,
        message_type: :outgoing,
        content: texto,
        content_attributes: { external_source: 'hermes_callback' }
      )
    end

    it 'nao manda para triagem quando a IA apenas cumprimenta de volta (caso conv 126)' do
      responde_antes('Boa noite, Rodrigo! 😊 Como posso te ajudar?')

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'Boa noite, Rodrigo! 😊 Aqui é a Duda da Academia Dom Bosco. Como posso te ajudar?' }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).not_to include('triagem_loop_detectado')
    end

    it 'nao manda para triagem com apenas duas respostas identicas' do
      responde_antes('Claro! Voce quer saber de valores, horarios ou das aulas?')

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'Claro! Voce quer saber de valores, horarios ou das aulas?' }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).not_to include('triagem_loop_detectado')
    end

    it 'manda para triagem quando a IA repete a mesma resposta pela terceira vez' do
      responde_antes('Claro! Voce quer saber de valores, horarios ou das aulas?')
      responde_antes('Claro! Voce quer saber de valores, horarios ou das aulas?')

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'Claro! Voce quer saber de valores, horarios ou das aulas?' }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).to include('triagem_loop_detectado')
    end

    it 'nao manda para triagem quando a terceira resposta avanca o atendimento' do
      responde_antes('Claro! Voce quer saber de valores, horarios ou das aulas?')
      responde_antes('Claro! Voce quer saber de valores, horarios ou das aulas?')

      post '/webhooks/captain/hermes_callback',
           params: { inbox_id: inbox.id, content: 'O plano anual sai por 12x de R$ 149,90 e inclui musculacao.' }

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.label_list).not_to include('triagem_loop_detectado')
    end
  end
end
