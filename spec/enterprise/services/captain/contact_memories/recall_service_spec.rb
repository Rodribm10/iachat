require 'rails_helper'

RSpec.describe Captain::ContactMemories::RecallService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }

  before do
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:get_embedding).and_return(Array.new(1536, 0.1))
  end

  describe '#call' do
    it 'returns empty array when contact has no memories' do
      result = described_class.new(contact: contact, query_text: 'olá').call
      expect(result).to eq([])
    end

    it 'returns top-K active memories ordered by neighbor distance' do
      fact_a = create(:captain_contact_memory, contact: contact, account: account, content: 'Prefere Stilo', embedding: Array.new(1536, 0.1))
      fact_b = create(:captain_contact_memory, contact: contact, account: account, content: 'Aniversário 14/02', embedding: Array.new(1536, 0.2))
      create(:captain_contact_memory, contact: contact, account: account, deleted_at: Time.current, embedding: Array.new(1536, 0.1))

      result = described_class.new(contact: contact, query_text: 'quero reservar').call

      expect(result).to include(fact_a, fact_b)
      expect(result.size).to eq(2)
    end

    it 'respects unit scope filtering' do
      global_fact = create(:captain_contact_memory, contact: contact, account: account, scope: 'global', embedding: Array.new(1536, 0.1))
      unit5_fact = create(:captain_contact_memory, contact: contact, account: account, scope: 'unit:5', embedding: Array.new(1536, 0.1))
      unit7_fact = create(:captain_contact_memory, contact: contact, account: account, scope: 'unit:7', embedding: Array.new(1536, 0.1))

      result = described_class.new(contact: contact, query_text: 'x', unit_id: 5).call

      expect(result).to include(global_fact, unit5_fact)
      expect(result).not_to include(unit7_fact)
    end

    it 'respects top_k limit (default 5)' do
      7.times { create(:captain_contact_memory, contact: contact, account: account, embedding: Array.new(1536, rand)) }
      result = described_class.new(contact: contact, query_text: 'x').call
      expect(result.size).to eq(5)
    end

    it 'returns empty array when embedding_service raises' do
      allow(embedding_service).to receive(:get_embedding).and_raise(Captain::Llm::EmbeddingService::EmbeddingsError)
      create(:captain_contact_memory, contact: contact, account: account, embedding: Array.new(1536, 0.1))

      result = described_class.new(contact: contact, query_text: 'x').call
      expect(result).to eq([])
    end

    it 'returns empty array when timeout exceeded' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      create(:captain_contact_memory, contact: contact, account: account, embedding: Array.new(1536, 0.1))

      result = described_class.new(contact: contact, query_text: 'x').call
      expect(result).to eq([])
    end

    it 'skips memories with NULL embedding' do
      create(:captain_contact_memory, contact: contact, account: account, embedding: nil)
      result = described_class.new(contact: contact, query_text: 'x').call
      expect(result).to eq([])
    end
  end
end
