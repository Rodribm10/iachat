require 'rails_helper'

RSpec.describe Captain::ContactMemory, type: :model do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  describe 'validations' do
    it 'requires memory_type' do
      memory = build(:captain_contact_memory, account: account, contact: contact, memory_type: nil)
      expect(memory).not_to be_valid
    end

    it 'requires content' do
      memory = build(:captain_contact_memory, account: account, contact: contact, content: '')
      expect(memory).not_to be_valid
    end

    it 'requires evidence' do
      memory = build(:captain_contact_memory, account: account, contact: contact, evidence: '')
      expect(memory).not_to be_valid
    end

    it 'requires confidence between 0 and 1' do
      memory = build(:captain_contact_memory, account: account, contact: contact, confidence: 1.5)
      expect(memory).not_to be_valid
    end

    it 'rejects invalid memory_type' do
      memory = build(:captain_contact_memory, account: account, contact: contact, memory_type: 'invalid_type')
      expect(memory).not_to be_valid
    end

    it 'limits content to 1000 chars' do
      memory = build(:captain_contact_memory, account: account, contact: contact, content: 'a' * 1001)
      expect(memory).not_to be_valid
    end
  end

  describe '.active' do
    # rubocop:disable RSpec/LetSetup
    let!(:active) { create(:captain_contact_memory, account: account, contact: contact) }
    let!(:deleted) { create(:captain_contact_memory, account: account, contact: contact, deleted_at: Time.current) }
    let!(:superseded) { create(:captain_contact_memory, account: account, contact: contact, superseded_at: Time.current) }
    let!(:expired) { create(:captain_contact_memory, account: account, contact: contact, expires_at: 1.day.ago) }
    # rubocop:enable RSpec/LetSetup

    it 'excludes deleted, superseded, and expired' do
      expect(described_class.active).to contain_exactly(active)
    end
  end

  describe '.scope_compatible' do
    # rubocop:disable RSpec/LetSetup
    let!(:global_fact) { create(:captain_contact_memory, account: account, contact: contact, scope: 'global') }
    let!(:unit_fact) { create(:captain_contact_memory, account: account, contact: contact, scope: 'unit:5') }
    let!(:other_unit_fact) { create(:captain_contact_memory, account: account, contact: contact, scope: 'unit:7') }
    # rubocop:enable RSpec/LetSetup

    it 'returns global + facts for requested unit' do
      expect(described_class.scope_compatible(5)).to contain_exactly(global_fact, unit_fact)
    end

    it 'when unit_id is nil, returns only global' do
      expect(described_class.scope_compatible(nil)).to contain_exactly(global_fact)
    end
  end

  describe '#soft_delete!' do
    let(:memory) { create(:captain_contact_memory, account: account, contact: contact) }

    it 'sets deleted_at' do
      freeze_time do
        memory.soft_delete!
        expect(memory.reload.deleted_at).to eq(Time.current)
      end
    end
  end

  describe '#supersede_by!' do
    let(:old) { create(:captain_contact_memory, account: account, contact: contact) }
    let(:new_one) { create(:captain_contact_memory, account: account, contact: contact) }

    it 'links the old memory as superseded by the new one' do
      old.supersede_by!(new_one)
      expect(old.reload.superseded_by_id).to eq(new_one.id)
      expect(old.superseded_at).not_to be_nil
    end
  end

  describe '#recall_weight' do
    it 'returns 1.0 for non-expired' do
      memory = build(:captain_contact_memory, account: account, contact: contact, expires_at: 1.day.from_now)
      expect(memory.recall_weight).to eq(1.0)
    end

    it 'returns 0.7 for expired' do
      memory = build(:captain_contact_memory, account: account, contact: contact, expires_at: 1.day.ago)
      expect(memory.recall_weight).to eq(0.7)
    end
  end
end
