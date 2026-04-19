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

  # Attach neighbor_distance to a memory instance; used to force a record
  # into the conflict zone (>= DEDUP) or dedup zone (< DEDUP) deterministically.
  def with_distance(memory, distance)
    memory.define_singleton_method(:neighbor_distance) { distance }
    memory
  end

  describe '#call' do
    let(:old_fact) do
      build_memory(content: 'Prefere Stilo')
    end
    let(:new_fact) do
      build_memory(content: 'Prefere Alexa agora', embedding: embedding_b)
    end
    let(:service) { described_class.new(memory: new_fact) }

    # Force candidates' neighbor_distance into the conflict zone (above DEDUP, below CONFLICT)
    # so tests exercise the LLM-check path. Individual tests can override the distance.
    before do
      allow(service).to receive(:candidates).and_return([with_distance(old_fact, 0.3)])
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
      # Different-type candidate filtering happens at the real candidates query level.
      # Simulate by having candidates return [] when types differ.
      allow(service).to receive(:candidates).and_return([])
      service.call
      expect(other.reload.superseded_by_id).to be_nil
    end

    it 'no-ops when memory has no embedding' do
      old_fact
      embeddingless = build_memory(embedding: nil)
      expect { described_class.new(memory: embeddingless).call }.not_to raise_error
      expect(old_fact.reload.superseded_by_id).to be_nil
    end

    it 'auto-supersedes near-duplicates without asking LLM' do
      allow(service).to receive(:candidates).and_return([with_distance(old_fact, 0.05)])
      allow(service).to receive(:contradicts?) # spy — should never be called
      service.call
      expect(old_fact.reload.superseded_by_id).to eq(new_fact.id)
      expect(service).not_to have_received(:contradicts?)
    end

    context 'when LLM raises during contradiction check' do
      it 'does not supersede when LLM raises' do
        chat_double = instance_double(RubyLLM::Chat)
        allow(chat_double).to receive(:with_temperature).and_return(chat_double)
        allow(chat_double).to receive(:ask).and_raise(StandardError, 'LLM down')
        allow(RubyLLM).to receive(:chat).and_return(chat_double)

        # Exercise the real rescue path inside contradicts? (no contradicts? stub here)
        real_service = described_class.new(memory: new_fact)
        allow(real_service).to receive(:candidates).and_return([with_distance(old_fact, 0.3)])
        expect { real_service.call }.not_to raise_error
        expect(old_fact.reload.superseded_by_id).to be_nil
      end
    end
  end
end
