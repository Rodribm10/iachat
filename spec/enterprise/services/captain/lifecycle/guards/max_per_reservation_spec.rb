# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::MaxPerReservation do
  subject(:guard) { described_class.new(delivery) }

  let(:reservation) { create(:captain_reservation) }
  let(:delivery) { create(:captain_lifecycle_delivery, captain_reservation: reservation) }

  it 'passes with 0 sent deliveries' do
    expect(guard.check).to eq(action: :pass)
  end

  it 'passes with 4 sent deliveries' do
    4.times do
      create(:captain_lifecycle_delivery,
             captain_reservation: reservation, status: 'sent', origin: 'scheduled_lifecycle')
    end
    expect(guard.check).to eq(action: :pass)
  end

  it 'skips at 5 sent deliveries' do
    5.times do
      create(:captain_lifecycle_delivery,
             captain_reservation: reservation, status: 'sent', origin: 'scheduled_lifecycle')
    end
    expect(guard.check).to eq(action: :skip, reason: 'max_reached')
  end

  it 'ignores concierge_reply origin' do
    10.times do
      create(:captain_lifecycle_delivery,
             captain_reservation: reservation, status: 'sent', origin: 'concierge_reply')
    end
    expect(guard.check).to eq(action: :pass)
  end
end
