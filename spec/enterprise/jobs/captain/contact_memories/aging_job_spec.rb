require 'rails_helper'

RSpec.describe Captain::ContactMemories::AgingJob do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  it 'soft-deletes expired reclamacao (delete on expire type)' do
    mem = create(:captain_contact_memory, account: account, contact: contact, memory_type: 'reclamacao', expires_at: 1.day.ago)
    described_class.perform_now
    expect(mem.reload.deleted_at).not_to be_nil
  end

  it 'does NOT soft-delete expired preferencia (reduce-weight type)' do
    mem = create(:captain_contact_memory, account: account, contact: contact, memory_type: 'preferencia', expires_at: 1.day.ago)
    described_class.perform_now
    expect(mem.reload.deleted_at).to be_nil
  end

  it 'applies LRU soft-delete when contact exceeds 50 active facts' do
    55.times do |i|
      create(:captain_contact_memory, account: account, contact: contact, last_verified_at: i.days.ago)
    end
    described_class.perform_now
    expect(Captain::ContactMemory.where(contact: contact).active.count).to eq(50)
  end
end
