require 'rails_helper'

RSpec.describe Captain::ContactMemories::HardDeleteExpiredJob do
  it 'destroys records soft-deleted more than 30 days ago' do
    old = create(:captain_contact_memory, deleted_at: 40.days.ago)
    recent = create(:captain_contact_memory, deleted_at: 10.days.ago)
    active = create(:captain_contact_memory, deleted_at: nil)

    described_class.perform_now

    expect(Captain::ContactMemory.exists?(old.id)).to be(false)
    expect(Captain::ContactMemory.exists?(recent.id)).to be(true)
    expect(Captain::ContactMemory.exists?(active.id)).to be(true)
  end
end
