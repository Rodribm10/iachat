# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::EventResolver do
  let(:reservation) do
    build(:captain_reservation,
          check_in_at: Time.zone.parse('2026-04-20 22:00:00'),
          check_out_at: Time.zone.parse('2026-04-21 12:00:00'),
          updated_at: Time.zone.parse('2026-04-19 10:00:00'))
  end

  describe '.resolve' do
    it 'returns check_in_at for checkin.scheduled_at' do
      expect(described_class.resolve(reservation, 'checkin.scheduled_at'))
        .to eq(reservation.check_in_at)
    end

    it 'returns check_out_at for checkout.scheduled_at' do
      expect(described_class.resolve(reservation, 'checkout.scheduled_at'))
        .to eq(reservation.check_out_at)
    end

    it 'returns updated_at for reservation.confirmed' do
      expect(described_class.resolve(reservation, 'reservation.confirmed'))
        .to eq(reservation.updated_at)
    end

    it 'returns nil for checkin.detected (not yet supported)' do
      expect(described_class.resolve(reservation, 'checkin.detected')).to be_nil
    end

    it 'returns nil for checkout.detected (not yet supported)' do
      expect(described_class.resolve(reservation, 'checkout.detected')).to be_nil
    end

    it 'raises for unknown event' do
      expect { described_class.resolve(reservation, 'unknown.event') }
        .to raise_error(ArgumentError, /unknown event/)
    end
  end
end
