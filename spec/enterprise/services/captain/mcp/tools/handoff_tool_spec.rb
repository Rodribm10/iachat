# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Mcp::Tools::HandoffTool, type: :model do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:tool) { described_class.new }

  def handoff(args = {})
    tool.call({ 'conversation_id' => conversation.id }.merge(args), context: {})
  end

  # `open` é o que cala a IA: HookExecutionService só aciona o Captain quando a
  # conversa está `pending`. Sem essa transição a transferência é só uma frase.
  it 'tira a conversa da IA colocando em aberto' do
    expect { handoff }.to change { conversation.reload.status }.from('pending').to('open')
  end

  it 'marca as etiquetas que a equipe filtra e que barram novo dispatch' do
    handoff('reason' => 'cobranca')

    labels = conversation.reload.label_list
    expect(labels).to include('triagem_humana')
    expect(labels).to include('triagem_cobranca')
  end

  it 'cai no motivo padrao quando o assistente manda um motivo desconhecido' do
    handoff('reason' => 'qualquer_coisa_inventada')

    expect(conversation.reload.label_list).to include('triagem_sem_resposta_segura')
  end

  it 'registra a linha de contexto do assistente como nota interna' do
    handoff('note' => 'Cliente quer cancelar e ja falou em Procon.')

    note = conversation.reload.messages.where(private: true).last
    expect(note.content).to eq('Cliente quer cancelar e ja falou em Procon.')
    expect(note.content_attributes).to include('external_source' => 'hermes_handoff_context')
  end

  it 'nao cria nota de contexto quando o assistente nao manda uma' do
    handoff

    contexto = conversation.reload.messages.where(private: true).select do |m|
      m.content_attributes['external_source'] == 'hermes_handoff_context'
    end
    expect(contexto).to be_empty
  end

  it 'devolve erro sem transferir quando a conversa nao existe' do
    result = tool.call({ 'conversation_id' => 0 }, context: {})

    expect(result.to_s).to include('não encontrada')
    expect(conversation.reload).to be_pending
  end

  it 'e idempotente: chamar de novo nao duplica a nota de triagem' do
    handoff
    primeira = conversation.reload.messages.where(private: true).count

    handoff
    expect(conversation.reload.messages.where(private: true).count).to eq(primeira)
  end
end
