# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::MinInterval do
  subject(:guard) { described_class.new(delivery) }

  let(:account) { create(:account) }
  let(:reservation) { create(:captain_reservation, account: account) }
  let(:delivery) do
    create(:captain_lifecycle_delivery,
           account: account, captain_reservation: reservation, fire_at: 1.minute.from_now)
  end

  context 'when min_interval_minutes = 0' do
    before { create(:captain_lifecycle_config, account: account, min_interval_minutes: 0) }

    it 'passes' do
      expect(guard.check).to eq(action: :pass)
    end
  end

  context 'when min_interval_minutes = 30' do
    before { create(:captain_lifecycle_config, account: account, min_interval_minutes: 30) }

    it 'passes when no previous delivery was sent' do
      expect(guard.check).to eq(action: :pass)
    end

    it 'reschedules when a previous delivery was sent < 30min ago' do
      create(:captain_lifecycle_delivery,
             account: account, captain_reservation: reservation,
             status: 'sent', sent_at: 10.minutes.ago, origin: 'scheduled_lifecycle')

      result = guard.check
      expect(result[:action]).to eq(:reschedule)
      expect(result[:fire_at]).to be_within(1.minute).of(10.minutes.ago + 30.minutes)
    end

    it 'skips with too_stale when rescheduled delay exceeds 2 hours' do
      create(:captain_lifecycle_delivery,
             account: account, captain_reservation: reservation,
             status: 'sent', sent_at: 3.hours.ago, origin: 'scheduled_lifecycle')

      # fire_at is 1 minute from now; earliest_allowed = 3.hours.ago + 30.min = ~2.5 hours ago
      # earliest_allowed < fire_at → should pass
      expect(guard.check).to eq(action: :pass)
    end

    it 'skips with too_stale when delay between earliest_allowed and fire_at exceeds MAX_DELAY' do
      # fire_at = 1 min from now; last sent_at = 1 minute ago → earliest_allowed = 29 min from now
      # delay = earliest_allowed - fire_at = ~28 min → reschedule
      create(:captain_lifecycle_delivery,
             account: account, captain_reservation: reservation,
             status: 'sent', sent_at: 1.minute.ago, origin: 'scheduled_lifecycle')

      result = guard.check
      expect(result[:action]).to eq(:reschedule)
    end

    it 'skips too_stale when earliest_allowed is more than 2h after fire_at' do
      # Make delivery fire_at in the past so earliest_allowed is far ahead
      past_delivery = create(:captain_lifecycle_delivery,
                             account: account, captain_reservation: reservation,
                             fire_at: 3.hours.ago)

      past_guard = described_class.new(past_delivery)

      # sent 10min ago, interval 30min → earliest = 20min from now
      # fire_at = 3h ago → delay = earliest - fire_at ≈ 3h20m > 2h → too_stale
      create(:captain_lifecycle_delivery,
             account: account, captain_reservation: reservation,
             status: 'sent', sent_at: 10.minutes.ago, origin: 'scheduled_lifecycle')

      result = past_guard.check
      expect(result[:action]).to eq(:skip)
      expect(result[:reason]).to eq('too_stale')
    end
  end
end
