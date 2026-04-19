require 'rails_helper'

RSpec.describe Captain::ContactMemories::UpdateEmbeddingJob do
  let(:memory) { create(:captain_contact_memory) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }

  before do
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:get_embedding).and_return(Array.new(1536, 0.5))
  end

  it 'sets embedding on the memory' do
    described_class.perform_now(memory.id)
    stored = memory.reload.embedding
    # Model uses `has_neighbors :embedding, normalize: true`, so pgvector stores
    # the L2-normalized vector rather than the raw stub. We assert the embedding
    # is persisted with the correct dimensionality and reflects the stubbed
    # uniform vector (all components equal after normalization).
    expect(stored).to be_present
    expect(stored.size).to eq(1536)
    expect(stored.uniq.size).to eq(1)
    expect(stored.first).to be_within(1e-6).of(1.0 / Math.sqrt(1536))
  end

  it 'does not enqueue ContradictionCheckerJob inside itself' do
    expect { described_class.perform_now(memory.id) }
      .not_to have_enqueued_job(Captain::ContactMemories::ContradictionCheckerJob)
  end

  it 'enqueues ContradictionCheckerJob after setting embedding when configured' do
    expect { described_class.perform_now(memory.id, run_contradiction_check: true) }
      .to have_enqueued_job(Captain::ContactMemories::ContradictionCheckerJob).with(memory.id)
  end

  it 'tolerates a missing memory silently' do
    expect { described_class.perform_now(99_999_999) }.not_to raise_error
  end
end
