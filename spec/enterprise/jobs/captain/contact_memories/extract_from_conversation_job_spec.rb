require 'rails_helper'

RSpec.describe Captain::ContactMemories::ExtractFromConversationJob do
  let(:account) { create(:account, custom_attributes: { 'captain_contact_memory_extraction_enabled' => true }) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:extracted_facts) do
    [
      { memory_type: 'preferencia', content: 'Prefere Stilo', evidence: 'disse x', confidence: 0.9, scope: 'global' }
    ]
  end

  before do
    allow_any_instance_of(Captain::ContactMemories::ExtractionService).to receive(:call).and_return(extracted_facts) # rubocop:disable RSpec/AnyInstance
  end

  it 'skips when extraction flag is off' do
    account.update!(custom_attributes: { 'captain_contact_memory_extraction_enabled' => false })
    expect { described_class.perform_now(conversation.id) }.not_to change(Captain::ContactMemory, :count)
  end

  it 'persists facts with source attribution' do
    described_class.perform_now(conversation.id)
    memory = Captain::ContactMemory.last
    expect(memory.content).to eq('Prefere Stilo')
    expect(memory.source_conversation_id).to eq(conversation.id)
    expect(memory.source_inbox_id).to eq(conversation.inbox_id)
  end

  it 'is idempotent when re-run for the same conversation' do
    described_class.perform_now(conversation.id)
    expect { described_class.perform_now(conversation.id) }.not_to change(Captain::ContactMemory, :count)
  end

  it 'enqueues embedding job for each created memory' do
    expect { described_class.perform_now(conversation.id) }
      .to have_enqueued_job(Captain::ContactMemories::UpdateEmbeddingJob).with(anything, run_contradiction_check: true)
  end

  it 'sets last_verified_at to now' do
    freeze_time do
      described_class.perform_now(conversation.id)
      expect(Captain::ContactMemory.last.last_verified_at).to eq(Time.current)
    end
  end

  it 'applies TTL expires_at for types that expire' do
    allow_any_instance_of(Captain::ContactMemories::ExtractionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:call).and_return(
        [{ memory_type: 'reclamacao', content: 'x', evidence: 'y', confidence: 0.9, scope: 'unit:1' }]
      )
    freeze_time do
      described_class.perform_now(conversation.id)
      memory = Captain::ContactMemory.last
      expect(memory.expires_at).to eq(180.days.from_now)
    end
  end

  it 'leaves expires_at null for types without TTL' do
    allow_any_instance_of(Captain::ContactMemories::ExtractionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:call).and_return(
        [{ memory_type: 'restricao', content: 'alergia', evidence: 'y', confidence: 0.9, scope: 'global' }]
      )
    described_class.perform_now(conversation.id)
    expect(Captain::ContactMemory.last.expires_at).to be_nil
  end

  it 'rolls back all facts and does not enqueue jobs if any fact fails to persist' do
    bad_facts = [
      { memory_type: 'preferencia', content: 'A', evidence: 'x', confidence: 0.9, scope: 'global' },
      { memory_type: 'invalid_type_not_in_enum', content: 'B', evidence: 'y', confidence: 0.9, scope: 'global' }
    ]
    allow_any_instance_of(Captain::ContactMemories::ExtractionService) # rubocop:disable RSpec/AnyInstance
      .to receive(:call).and_return(bad_facts)

    expect do
      expect { described_class.perform_now(conversation.id) }.to raise_error(ActiveRecord::RecordInvalid)
    end.not_to change(Captain::ContactMemory, :count)

    embedding_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select do |j|
      j[:job] == Captain::ContactMemories::UpdateEmbeddingJob
    end
    expect(embedding_jobs).to be_empty
  end
end
