require 'rails_helper'

RSpec.describe Captain::Guards::PromptLeak do
  describe '.leak?' do
    describe 'vazamento de system prompt' do
      [
        '[Contexto] Você é a atendente...',
        '<contexto>dados da unidade</contexto>',
        '# System Context',
        '[Identity] Jasmine',
        '[Context] unidade PRIME',
        'You are part of Captain, an AI assistant'
      ].each do |content|
        it("detecta #{content[0, 30]}") { expect(described_class.leak?(content)).to be(true) }
      end
    end

    describe 'vazamento de pensamento interno' do
      [
        'A IA deve confirmar o valor antes de reservar',
        'O assistente precisa checar a agenda',
        'Quando o cliente pedir fotos, envie o catálogo',
        'Consulte a ferramenta de disponibilidade',
        'Passe para o cliente o link de pagamento',
        'handoff_to_reservas',
        'captain--tools--generate_pix',
        'encaminhando para daniela_reservas',
        'handoff_imediato',
        'esse é o fluxo correto',
        '{"reasoning": "cliente quer preço"}',
        '"reaction_emoji": "👍"',
        'Olá {{ contact_name }}',
        '{% if unit %}'
      ].each do |content|
        it("detecta #{content[0, 30]}") { expect(described_class.leak?(content)).to be(true) }
      end
    end

    describe 'resposta legítima' do
      [
        'Boa tarde! Como posso ajudar?',
        'A suíte com hidromassagem está R$ 180 para 3 horas.',
        'Temos duas unidades na avenida.',
        'Peço desculpas pelo erro na reserva anterior.',
        'O cliente anterior elogiou muito essa suíte!',
        'Vou verificar a disponibilidade e já te falo.',
        ''
      ].each do |content|
        it("libera #{content.presence || '(vazio)'}") { expect(described_class.leak?(content)).to be(false) }
      end
    end

    it 'aceita conteúdo que não é String sem estourar' do
      expect(described_class.leak?(nil)).to be(false)
      expect(described_class.leak?(123)).to be(false)
    end
  end

  describe '.reason' do
    it 'distingue system_prompt de pensamento_interno' do
      expect(described_class.reason('[Contexto] blá')).to eq('system_prompt')
      expect(described_class.reason('A IA deve confirmar')).to eq('pensamento_interno')
      expect(described_class.reason('Boa tarde!')).to be_nil
    end
  end
end
