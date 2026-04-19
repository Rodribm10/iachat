require 'rails_helper'

RSpec.describe Captain::ContactMemories::PromptInjectionService do
  describe '#call' do
    it 'returns empty string when memories empty' do
      result = described_class.new(memories: []).call
      expect(result).to eq('')
    end

    it 'formats memories as XML block' do
      memories = [
        build_stubbed(:captain_contact_memory, memory_type: 'preferencia', content: 'Prefere Stilo', confidence: 0.92),
        build_stubbed(:captain_contact_memory, memory_type: 'data_comemorativa', content: 'Aniversário 14/02', confidence: 0.88)
      ]

      result = described_class.new(memories: memories).call

      expect(result).to include('<memoria_cliente>')
      expect(result).to include('<preferencia confidence="0.92">Prefere Stilo</preferencia>')
      expect(result).to include('<data_comemorativa confidence="0.88">Aniversário 14/02</data_comemorativa>')
      expect(result).to include('</memoria_cliente>')
    end

    it 'escapes XML-unsafe chars in content' do
      memories = [build_stubbed(:captain_contact_memory, content: 'texto com <tag> & ampersand')]
      result = described_class.new(memories: memories).call
      expect(result).to include('texto com &lt;tag&gt; &amp; ampersand')
    end
  end
end
