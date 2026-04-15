# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::ReservationActive do
  subject(:guard) { described_class.new(delivery) }

  let(:reservation) { create(:captain_reservation, status: 'confirmed') }
  let(:delivery) { create(:captain_lifecycle_delivery, captain_reservation: reservation) }

  it 'returns pass for active reservation' do
    expect(guard.check).to eq(action: :pass)
  end

  it 'returns skip for cancelled reservation' do
    reservation.update!(status: 'cancelled')
    expect(guard.check).to eq(action: :skip, reason: 'reservation_cancelled')
  end
end
