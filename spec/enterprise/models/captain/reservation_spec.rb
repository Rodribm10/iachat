# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Reservation do
  describe 'conversation marker sync' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
    let(:brand) { Captain::Brand.create!(account: account, name: 'Brand Test') }
    let(:unit) { Captain::Unit.create!(account: account, captain_brand_id: brand.id, name: 'Matriz') }

    let(:reservation) do
      described_class.create!(
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
        total_amount: 130
      )
    end

    it 'stores reservation marker snapshot in conversation additional_attributes' do
      marker = reservation.reload.conversation.reload.additional_attributes['reservation_marker']

      expect(marker['visible']).to be(true)
      expect(marker['reservation_id']).to eq(reservation.id)
      expect(marker['status']).to eq('pending_payment')
    end

    it 'updates marker snapshot when reservation state changes' do
      reservation.update!(status: :scheduled)

      marker = conversation.reload.additional_attributes['reservation_marker']
      expect(marker['status']).to eq('confirmed')
    end
  end

  describe 'set_captain_unit_id' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:brand) { Captain::Brand.create!(account: account, name: 'Brand Test') }

    def build_reservation
      described_class.new(
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        suite_identifier: 'Suite 101',
        check_in_at: 1.day.from_now.beginning_of_hour,
        check_out_at: 2.days.from_now.beginning_of_hour
      )
    end

    it 'uses captain_inbox unit when available' do
      unit = Captain::Unit.create!(
        account: account,
        captain_brand_id: brand.id,
        name: 'Unit via captain_inbox'
      )
      assistant = create(:captain_assistant, account: account)
      create(
        :captain_inbox,
        captain_assistant: assistant,
        inbox: inbox,
        captain_unit: unit
      )

      reservation = build_reservation
      reservation.validate

      expect(reservation.captain_unit_id).to eq(unit.id)
    end

    it 'falls back to unit linked directly to inbox' do
      unit = Captain::Unit.create!(
        account: account,
        captain_brand_id: brand.id,
        name: 'Unit via inbox link',
        inbox_id: inbox.id
      )
      assistant = create(:captain_assistant, account: account)
      create(
        :captain_inbox,
        captain_assistant: assistant,
        inbox: inbox,
        captain_unit: nil
      )

      reservation = build_reservation
      reservation.validate

      expect(reservation.captain_unit_id).to eq(unit.id)
    end
  end
end
