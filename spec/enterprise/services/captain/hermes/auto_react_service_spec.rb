require 'rails_helper'

RSpec.describe Captain::Hermes::AutoReactService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
  end

  def incoming(content)
    create(:message, conversation: conversation, inbox: inbox, account: account,
                     message_type: :incoming, content: content, source_id: SecureRandom.uuid)
  end

  def auto_react_count
    conversation.messages.to_a.count { |message| auto_react?(message) }
  end

  def last_auto_react
    conversation.messages.to_a.reverse.find { |message| auto_react?(message) }
  end

  def auto_react?(message)
    message.content_attributes['external_source'] == 'hermes_auto_react'
  end

  it 'does not react with affectionate emoji to farewell' do
    message = incoming('tchau, obrigado')

    described_class.maybe_react!(message)

    reaction = last_auto_react
    expect(reaction&.content).to eq('🙏')
  end

  it 'does not react to reservation or price context' do
    message = incoming('Qual o valor da suíte com hidro hoje?')

    expect do
      described_class.maybe_react!(message)
    end.not_to(change { auto_react_count })
  end

  it 'does not react to operational guest requests' do
    message = incoming('Pode subir o café aqui no quarto 110?')

    expect do
      described_class.maybe_react!(message)
    end.not_to(change { auto_react_count })
  end

  it 'does not react to emoji-only customer message' do
    message = incoming('❤️')

    expect do
      described_class.maybe_react!(message)
    end.not_to(change { auto_react_count })
  end

  it 'allows neutral confirmation reaction' do
    message = incoming('ok')

    described_class.maybe_react!(message)

    reaction = last_auto_react
    expect(reaction&.content).to eq('👍')
  end

  describe 'modo frequente (config auto_react_mode)' do
    before { assistant.update!(config: assistant.config.to_h.merge('auto_react_mode' => 'frequent')) }

    it 'reage a interesse declarado, que o modo conservador ignora' do
      described_class.maybe_react!(incoming('quero fazer a matricula'))

      expect(last_auto_react&.content).to eq('💪')
    end

    it 'reage a elogio' do
      described_class.maybe_react!(incoming('adorei a academia'))

      expect(last_auto_react&.content).to eq('😊')
    end

    it 'reage a confirmacao dentro de frase curta' do
      described_class.maybe_react!(incoming('ok, entendi'))

      expect(last_auto_react&.content).to eq('👍')
    end

    # Pergunta merece resposta, nao gesto — vale nos dois modos.
    it 'nao reage a pergunta' do
      described_class.maybe_react!(incoming('quero saber o valor do plano?'))

      expect(auto_react_count).to eq(0)
    end

    # No modo frequente a trava de contexto encolhe, mas nao some.
    it 'continua sem reagir a cobranca e cancelamento' do
      described_class.maybe_react!(incoming('quero cancelar meu plano'))

      expect(auto_react_count).to eq(0)
    end

    it 'passa a reagir a assunto que o modo conservador bloqueava por falar de valor' do
      described_class.maybe_react!(incoming('perfeito, fechado o plano anual'))

      expect(last_auto_react&.content).to eq('👍')
    end
  end

  describe 'modo off' do
    before { assistant.update!(config: assistant.config.to_h.merge('auto_react_mode' => 'off')) }

    it 'nao reage a nada' do
      described_class.maybe_react!(incoming('obrigado'))

      expect(auto_react_count).to eq(0)
    end
  end
end
