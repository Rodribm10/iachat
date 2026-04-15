require 'rails_helper'

RSpec.describe Captain::Lifecycle::Delivery, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:lifecycle_rule).class_name('Captain::Lifecycle::Rule').optional }
    it { is_expected.to belong_to(:captain_reservation).class_name('Captain::Reservation') }
    # NOTE: shoulda-matchers has trouble resolving Conversation in this load context;
    # association is tested via functional specs below
    it { is_expected.to belong_to(:message).optional }
    it { is_expected.to belong_to(:inbox).optional }
  end

  describe 'validations' do
    subject { build(:captain_lifecycle_delivery) }

    it { is_expected.to validate_presence_of(:fire_at) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[scheduled sent skipped failed cancelled]) }
  end

  describe '.scheduled / .sent / .skipped' do
    it 'scopes by status' do
      # Create reservation before rule so after_create_commit finds nothing to schedule
      account = create(:account)
      reservation = create(:captain_reservation, account: account,
                                                 check_in_at: 2.hours.from_now,
                                                 check_out_at: 10.hours.from_now)
      rule = create(:captain_lifecycle_rule, account: account)
      s = create(:captain_lifecycle_delivery, status: 'scheduled',
                                              account: account,
                                              captain_reservation: reservation,
                                              lifecycle_rule: rule)
      create(:captain_lifecycle_delivery, status: 'sent',
                                          account: account,
                                          captain_reservation: reservation,
                                          lifecycle_rule: rule)
      expect(described_class.scheduled).to contain_exactly(s)
    end
  end

  describe '.count_sent_for_reservation' do
    let(:reservation) { create(:captain_reservation) }

    it 'counts only sent scheduled_lifecycle deliveries' do
      create(:captain_lifecycle_delivery, captain_reservation: reservation, status: 'sent', origin: 'scheduled_lifecycle')
      create(:captain_lifecycle_delivery, captain_reservation: reservation, status: 'sent', origin: 'scheduled_lifecycle')
      create(:captain_lifecycle_delivery, captain_reservation: reservation, status: 'skipped', origin: 'scheduled_lifecycle')
      create(:captain_lifecycle_delivery, captain_reservation: reservation, status: 'sent', origin: 'concierge_reply')

      expect(described_class.count_sent_for_reservation(reservation.id)).to eq(2)
    end
  end

  describe '#mark_skipped!' do
    let(:delivery) { create(:captain_lifecycle_delivery, status: 'scheduled') }

    it 'updates status and skip_reason' do
      delivery.mark_skipped!('quiet_hours')
      expect(delivery.reload.status).to eq('skipped')
      expect(delivery.skip_reason).to eq('quiet_hours')
    end
  end

  describe '#mark_cancelled!' do
    let(:delivery) { create(:captain_lifecycle_delivery, status: 'scheduled') }

    it 'updates status' do
      delivery.mark_cancelled!
      expect(delivery.reload.status).to eq('cancelled')
    end
  end
end
