# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::QuietHours do
  subject(:guard) { described_class.new(delivery) }

  let(:account) { create(:account) }
  let(:reservation) { create(:captain_reservation, account: account) }
  let(:delivery) do
    create(:captain_lifecycle_delivery,
           account: account, captain_reservation: reservation, fire_at: fire_at)
  end

  context 'when quiet hours disabled' do
    let(:fire_at) { Time.zone.parse('2026-04-15 03:00:00') }

    before { create(:captain_lifecycle_config, account: account, quiet_hours_enabled: false) }

    it 'passes regardless of fire_at' do
      expect(guard.check).to eq(action: :pass)
    end
  end

  context 'when quiet hours enabled (23:00-08:00)' do
    before do
      create(:captain_lifecycle_config,
             account: account,
             quiet_hours_enabled: true,
             quiet_hours_from: '23:00',
             quiet_hours_to: '08:00')
    end

    context 'when fire_at is outside the window (14:00)' do
      let(:fire_at) { Time.zone.parse('2026-04-15 14:00:00') }

      it('passes') { expect(guard.check).to eq(action: :pass) }
    end

    context 'when fire_at is inside the window but close to end (07:45, delay 15min)' do
      let(:fire_at) { Time.zone.parse('2026-04-15 07:45:00') }

      it 'reschedules to 08:00' do
        result = guard.check
        expect(result[:action]).to eq(:reschedule)
        expect(result[:fire_at]).to eq(Time.zone.parse('2026-04-15 08:00:00'))
      end
    end

    context 'when fire_at is deep inside the window (03:00, delay 5h)' do
      let(:fire_at) { Time.zone.parse('2026-04-15 03:00:00') }

      it 'skips with too_stale' do
        expect(guard.check).to eq(action: :skip, reason: 'too_stale')
      end
    end

    context 'when fire_at is at 23:30 (delay until next 08:00 = 8.5h)' do
      let(:fire_at) { Time.zone.parse('2026-04-15 23:30:00') }

      it 'skips with too_stale' do
        expect(guard.check).to eq(action: :skip, reason: 'too_stale')
      end
    end
  end
end
