require 'rails_helper'

RSpec.describe Captain::Reservations::MarkerBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:brand) { Captain::Brand.create!(account: account, name: 'Brand Test') }
  let(:unit) { Captain::Unit.create!(account: account, captain_brand_id: brand.id, name: 'Matriz') }

  let(:reservation) do
    Captain::Reservation.create!(
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      conversation: conversation,
      captain_brand_id: brand.id,
      captain_unit_id: unit.id,
      suite_identifier: 'Suite 101',
      check_in_at: 1.day.from_now.beginning_of_hour,
      check_out_at: 2.days.from_now.beginning_of_hour,
      status: :pending_payment,
      total_amount: 130,
      metadata: { deposit_amount: 65 }
    )
  end

  describe '.ui_status' do
    it 'maps db statuses to ui statuses' do
      expect(described_class.ui_status(:draft)).to eq('draft')
      expect(described_class.ui_status(:pending_payment)).to eq('pending_payment')
      expect(described_class.ui_status(:scheduled)).to eq('confirmed')
      expect(described_class.ui_status(:active)).to eq('confirmed')
      expect(described_class.ui_status(:completed)).to eq('confirmed')
      expect(described_class.ui_status(:cancelled)).to eq('cancelled')
    end
  end

  describe '.build_for' do
    it 'returns hidden payload when reservation is blank' do
      expect(described_class.build_for(nil)).to eq('visible' => false)
    end

    it 'returns marker with deposit amount and status mapping' do
      marker = described_class.build_for(reservation)

      expect(marker['visible']).to be(true)
      expect(marker['status']).to eq('pending_payment')
      expect(marker['amount']).to eq(65.0)
      expect(marker['amount_kind']).to eq('deposit')
      expect(marker['reservation_id']).to eq(reservation.id)
    end

    it 'marks pix as not generated when pending payment has no charge' do
      marker = described_class.build_for(reservation)

      expect(marker['pix_copy_paste']).to be_nil
      expect(marker['pix_reason']).to eq('not_generated')
    end

    it 'marks pix as expired when charge is stale for pending payment' do
      Captain::PixCharge.create!(
        reservation: reservation,
        unit: unit,
        txid: SecureRandom.hex(8),
        status: 'active',
        created_at: 2.hours.ago,
        updated_at: 2.hours.ago
      )

      marker = described_class.build_for(reservation)
      expect(marker['pix_reason']).to eq('expired')
    end

    it 'returns pix payload when active charge has copy-paste value' do
      Captain::PixCharge.create!(
        reservation: reservation,
        unit: unit,
        txid: SecureRandom.hex(8),
        status: 'active',
        pix_copia_e_cola: '000201...',
        created_at: 10.minutes.ago,
        updated_at: 10.minutes.ago
      )

      marker = described_class.build_for(reservation)
      expect(marker['pix_copy_paste']).to eq('000201...')
      expect(marker['pix_reason']).to be_nil
    end
  end
end
