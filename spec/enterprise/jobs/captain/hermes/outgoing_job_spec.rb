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
  # `pending` e o funil da IA — o estado em que o job e agendado de verdade.
  let(:conversation) { create(:conversation, inbox: inbox, account: account, status: :pending) }
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

  it 'despacha quando a conversa esta no funil da IA' do
    run_job

    expect(client).to have_received(:dispatch)
  end

  # Regra do dono (25/08/2026): dentro do funil da IA nao existe trava. Antes,
  # uma label de triagem esquecida na conversa amordacava o agente pra sempre —
  # devolver pra IA nao adiantava, porque ninguem removia a label (conv 126 da
  # conta 2: handoff 14:44, devolvida 15:00, cliente falou 15:01 e 15:02, silencio).
  it 'despacha mesmo com label de triagem, se a conversa esta no funil da IA' do
    conversation.update_labels(%w[triagem_humana triagem_sem_resposta_segura])

    run_job

    expect(client).to have_received(:dispatch)
  end

  it 'nao despacha quando a conversa saiu do funil da IA' do
    conversation.update!(status: :open)

    run_job

    expect(client).not_to have_received(:dispatch)
  end

  # Cenario real do atraso: o job e agendado com inbox.typing_delay, e alguem
  # resolve a conversa antes dele rodar. A mensagem ja existe, entao nao ha
  # reabertura — o agente simplesmente cala.
  it 'nao despacha se a conversa foi resolvida entre o agendamento e a execucao' do
    message = incoming
    conversation.update!(status: :resolved)

    described_class.new.perform(conversation.id, message.id)

    expect(client).not_to have_received(:dispatch)
  end

  # Comportamento desejado do Chatwoot: cliente que volta depois de resolvida
  # reabre a conversa JA no funil da IA — por isso o agente responde.
  it 'atende cliente que volta depois da conversa resolvida' do
    conversation.update!(status: :resolved)

    run_job

    expect(conversation.reload).to be_pending
    expect(client).to have_received(:dispatch)
  end

  # Trava intencional: alguem marcou "aqui a IA nao fala" (funcionarios, contatos
  # que o time prefere atender a mao). Essa vale ate dentro do funil da IA.
  it 'nao despacha quando a IA foi desligada por marcacao, mesmo no funil da IA' do
    conversation.update_labels(%w[duda_desligada])

    run_job

    expect(client).not_to have_received(:dispatch)
  end

  it 'a triagem humana tira a conversa do funil e por isso o agente cala' do
    Captain::Hermes::HumanTriageService.perform(conversation: conversation, reason: 'sem_resposta_segura')

    expect(conversation.reload).to be_open
    run_job

    expect(client).not_to have_received(:dispatch)
  end

  # Devolver pra IA volta a despachar E limpa as labels de triagem (o release
  # continua valendo — elas sujam filtro e relatorio, so nao bloqueiam mais).
  it 'volta a despachar quando a conversa e devolvida para o funil da IA' do
    Captain::Hermes::HumanTriageService.perform(conversation: conversation, reason: 'sem_resposta_segura')
    expect(conversation.reload.label_list).to include('triagem_humana')

    conversation.update!(status: :pending)
    expect(conversation.reload.label_list).to be_empty

    run_job

    expect(client).to have_received(:dispatch)
  end
end
