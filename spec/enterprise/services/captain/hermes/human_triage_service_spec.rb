require 'rails_helper'

RSpec.describe Captain::Hermes::HumanTriageService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
  end

  def release_notes
    conversation.messages.to_a.select { |message| message.content_attributes['external_source'] == 'hermes_human_triage_release' }
  end

  describe '.release' do
    # Regressao (conv 126 da conta 2, 25/08/2026): handoff as 14:44 aplicou
    # triagem_humana + triagem_sem_resposta_segura; a conversa foi devolvida
    # (status pending) as 15:00 e as labels nunca saiam sozinhas.
    it 'remove triagem_humana e a label do motivo quando a conversa e liberada' do
      conversation.update_labels(%w[triagem_humana triagem_sem_resposta_segura])

      result = described_class.release(conversation: conversation)

      expect(result).to be true
      expect(conversation.reload.label_list).to be_empty
    end

    it 'remove hermes_placeholder (a outra label do guard)' do
      conversation.update_labels(%w[hermes_placeholder lead_novo])

      described_class.release(conversation: conversation)

      expect(conversation.reload.label_list).to contain_exactly('lead_novo')
    end

    it 'preserva duda_desligada e lead_novo, e as demais labels operacionais' do
      preserved = %w[duda_desligada cliente_aguardando demora_critica objecao_sem_resposta lead_novo convenio_wellhub visita_marcada]
      conversation.update_labels(preserved + %w[triagem_humana triagem_loop_detectado])

      described_class.release(conversation: conversation)

      expect(conversation.reload.label_list).to match_array(preserved)
    end

    it 'nao mexe em conversa sem label de triagem, e nao cria nota' do
      conversation.update_labels(%w[lead_novo])

      result = described_class.release(conversation: conversation)

      expect(result).to be false
      expect(conversation.reload.label_list).to contain_exactly('lead_novo')
      expect(release_notes).to be_empty
    end

    it 'e idempotente: a segunda chamada nao faz nada nem duplica nota' do
      conversation.update_labels(%w[triagem_humana])

      first_result = described_class.release(conversation: conversation)
      second_result = described_class.release(conversation: conversation)

      expect(first_result).to be true
      expect(second_result).to be false
      expect(release_notes.size).to eq(1)
    end

    it 'registra uma nota interna privada explicando a liberacao' do
      conversation.update_labels(%w[triagem_humana triagem_erro_tecnico])

      described_class.release(conversation: conversation)

      expect(release_notes.size).to eq(1)
      note = release_notes.first
      expect(note.private?).to be true
      expect(note.content).to include('devolvida para a IA')
    end

    it 'retorna false para conversa em branco' do
      expect(described_class.release(conversation: nil)).to be false
    end
  end

  # Prova que .perform e .release sao operacoes simetricas e inversas: o que
  # um aplica, o outro desfaz por completo.
  describe 'ciclo perform -> release' do
    it 'devolve a conversa ao estado sem nenhuma label de triagem' do
      described_class.perform(conversation: conversation, reason: 'loop_detectado')
      expect(conversation.reload.label_list).to include('triagem_humana', 'triagem_loop_detectado')

      described_class.release(conversation: conversation)

      expect(conversation.reload.label_list).to be_empty
    end
  end
end
