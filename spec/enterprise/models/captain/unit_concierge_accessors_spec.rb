# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Unit do
  subject(:unit) { described_class.new(concierge_config: config) }

  context 'when config is empty' do
    let(:config) { {} }

    it '#concierge_persona_name defaults to Sofia' do
      expect(unit.concierge_persona_name).to eq('Sofia')
    end

    it '#concierge_knowledge is empty string' do
      expect(unit.concierge_knowledge).to eq('')
    end

    it '#concierge_variables is empty hash' do
      expect(unit.concierge_variables).to eq({})
    end
  end

  context 'when config is populated' do
    let(:config) do
      {
        'persona_name' => 'Alice',
        'knowledge' => '## Sobre o hotel\n...',
        'variables' => { 'wifi_password' => 'hotel1001' }
      }
    end

    it 'returns persona_name from config' do
      expect(unit.concierge_persona_name).to eq('Alice')
    end

    it 'returns knowledge from config' do
      expect(unit.concierge_knowledge).to eq('## Sobre o hotel\n...')
    end

    it 'returns variables from config' do
      expect(unit.concierge_variables).to eq('wifi_password' => 'hotel1001')
    end
  end

  describe '#concierge_configured?' do
    it 'is false when inbox missing' do
      unit = described_class.new(concierge_inbox_id: nil)
      expect(unit.concierge_configured?).to be(false)
    end

    it 'is true when inbox present' do
      inbox = create(:inbox)
      unit = described_class.new(concierge_inbox_id: inbox.id)
      expect(unit.concierge_configured?).to be(true)
    end
  end
end
