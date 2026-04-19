require 'rails_helper'

RSpec.describe Captain::ContactMemories::ContradictionCheckerJob do
  let(:memory) { create(:captain_contact_memory) }

  it 'delegates to ContradictionCheckerService' do
    service = instance_double(Captain::ContactMemories::ContradictionCheckerService, call: nil)
    expect(Captain::ContactMemories::ContradictionCheckerService).to receive(:new).with(memory: memory).and_return(service)
    described_class.perform_now(memory.id)
  end

  it 'no-ops on missing memory' do
    expect { described_class.perform_now(99_999_999) }.not_to raise_error
  end
end
