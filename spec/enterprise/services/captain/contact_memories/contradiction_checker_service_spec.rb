require 'rails_helper'

RSpec.describe Captain::ContactMemories::ContradictionCheckerService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:embedding_a) { Array.new(1536, 0.1) }
  let(:embedding_b) { Array.new(1536, 0.15) }

  def build_memory(attrs = {})
    create(
      :captain_contact_memory,
      {
        account: account,
        contact: contact,
        memory_type: 'preferencia',
        embedding: embedding_a
      }.merge(attrs)
    )
  end

  describe '#call' do
    let(:old_fact) do
      build_memory(content: 'Prefere Stilo')
    end
    let(:new_fact) do
      build_memory(content: 'Prefere Alexa agora', embedding: embedding_b)
    end
    let(:service) { described_class.new(memory: new_fact) }

    before do
      allow(service).to receive(:contradicts?).and_return(true)
    end

    it 'supersedes contradictory older facts of same type' do
      old_fact
      service.call
      expect(old_fact.reload.superseded_by_id).to eq(new_fact.id)
      expect(old_fact.superseded_at).not_to be_nil
    end

    it 'does not supersede non-contradictory facts' do
      allow(service).to receive(:contradicts?).and_return(false)
      old_fact
      service.call
      expect(old_fact.reload.superseded_by_id).to be_nil
    end

    it 'does not supersede across different memory types' do
      other = build_memory(memory_type: 'reclamacao')
      service.call
      expect(other.reload.superseded_by_id).to be_nil
    end

    it 'no-ops when memory has no embedding' do
      old_fact
      embeddingless = build_memory(embedding: nil)
      expect { described_class.new(memory: embeddingless).call }.not_to raise_error
      expect(old_fact.reload.superseded_by_id).to be_nil
    end
  end
end
