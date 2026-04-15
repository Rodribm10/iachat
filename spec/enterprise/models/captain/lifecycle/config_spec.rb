# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Config, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:opt_out_label).class_name('Label').optional }
  end

  describe 'validations' do
    subject { build(:captain_lifecycle_config) }

    it { is_expected.to validate_uniqueness_of(:account_id) }
    it { is_expected.to validate_numericality_of(:min_interval_minutes).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:pause_on_customer_reply_within_minutes).is_greater_than_or_equal_to(0) }
  end

  describe '.for_account' do
    let(:account) { create(:account) }

    it 'returns existing config when present' do
      config = create(:captain_lifecycle_config, account: account)
      expect(described_class.for_account(account)).to eq(config)
    end

    it 'creates default config when missing' do
      expect { described_class.for_account(account) }
        .to change(described_class, :count).by(1)
    end

    it 'defaults have quiet_hours disabled' do
      config = described_class.for_account(account)
      expect(config.quiet_hours_enabled).to be(false)
    end
  end
end
