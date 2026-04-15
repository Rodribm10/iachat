# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Reservation, '#lifecycle_hooks' do
  let(:account) { create(:account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:unit) { Captain::Unit.create!(account: account, name: 'Test', brand: brand) }

  describe 'after create' do
    it 'calls Scheduler.schedule_for' do
      expect(Captain::Lifecycle::Scheduler).to receive(:schedule_for).with(kind_of(described_class))
      create(:captain_reservation,
             account: account, unit: unit,
             check_in_at: 2.hours.from_now, check_out_at: 10.hours.from_now)
    end
  end

  describe 'after update (status → cancelled)' do
    let(:reservation) do
      allow(Captain::Lifecycle::Scheduler).to receive(:schedule_for)
      create(:captain_reservation,
             account: account, unit: unit,
             check_in_at: 2.hours.from_now, check_out_at: 10.hours.from_now)
    end

    it 'cancels pending deliveries' do
      expect(Captain::Lifecycle::Scheduler).to receive(:cancel_pending).with(reservation)
      reservation.update!(status: 'cancelled')
    end
  end

  describe 'after update (check_in_at changed)' do
    let(:reservation) do
      allow(Captain::Lifecycle::Scheduler).to receive(:schedule_for)
      create(:captain_reservation,
             account: account, unit: unit,
             check_in_at: 2.hours.from_now, check_out_at: 10.hours.from_now)
    end

    it 'reschedules checkin-based deliveries' do
      expect(Captain::Lifecycle::Scheduler).to receive(:reschedule_for_checkin_change).with(reservation)
      reservation.update!(check_in_at: 3.hours.from_now)
    end
  end
end
