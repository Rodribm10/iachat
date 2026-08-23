require 'rails_helper'

describe Captain::Hermes::DelayedReplyJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
  end

  def run_job(content)
    job = described_class.new
    allow(job).to receive(:sleep)
    allow(job).to receive(:send_typing)
    job.perform(conversation.id, content)
  end

  def outgoing_contents
    conversation.messages.where(message_type: :outgoing).reorder(:id).pluck(:content)
  end

  it 'posta uma unica mensagem quando nao ha delimitador' do
    run_job("Oi! Tudo bem?\n\nComo posso ajudar?")

    expect(outgoing_contents).to eq(["Oi! Tudo bem?\n\nComo posso ajudar?"])
  end

  # Message splitting: linha contendo apenas ||| separa a resposta em baloes,
  # como o SOUL das atendentes ja pedia ("quebro em ate 3 mensagens") sem que o
  # encanamento entregasse — tudo saia num balao so.
  it 'divide em baloes na linha ||| preservando a ordem' do
    run_job("Pode sim!\n|||\nA experimental é grátis 😊\n|||\nPrefere terça ou quinta?")

    expect(outgoing_contents).to eq(['Pode sim!', 'A experimental é grátis 😊', 'Prefere terça ou quinta?'])
  end

  it 'tolera espacos ao redor do delimitador e descarta partes vazias' do
    run_job("Primeira\n ||| \n\n|||\nSegunda")

    expect(outgoing_contents).to eq(%w[Primeira Segunda])
  end

  it 'nao quebra ||| no meio de uma linha com texto' do
    run_job('use o codigo A|||B na catraca')

    expect(outgoing_contents).to eq(['use o codigo A|||B na catraca'])
  end

  it 'limita a 4 baloes juntando o excedente no ultimo' do
    content = (1..6).map { |i| "parte #{i}" }.join("\n|||\n")
    run_job(content)

    expect(outgoing_contents.length).to eq(4)
    expect(outgoing_contents.last).to include('parte 4', 'parte 5', 'parte 6')
  end

  it 'entrega o conteudo original quando ele e so delimitador' do
    run_job("|||\n|||")

    expect(outgoing_contents.length).to eq(1)
  end
end
