# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Payments::ProactivePixPollingSchedulerJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:brand) { Captain::Brand.create!(account: account, name: 'Brand Test') }

  let(:eligible_unit) do
    Captain::Unit.create!(
      account: account,
      captain_brand_id: brand.id,
      name: 'Unit Eligible',
      inter_client_id: 'client-id',
      inter_client_secret: 'client-secret',
      inter_pix_key: '11999999999',
      inter_account_number: '210339349',
      inter_cert_content: 'cert-content',
      inter_key_content: 'key-content',
      proactive_pix_polling_enabled: true
    )
  end

  let(:ineligible_unit) do
    Captain::Unit.create!(
      account: account,
      captain_brand_id: brand.id,
      name: 'Unit Ineligible',
      inter_client_id: 'client-id',
      inter_client_secret: 'client-secret',
      inter_pix_key: '11888888888',
      inter_account_number: '318244055',
      inter_cert_content: 'cert-content',
      inter_key_content: 'key-content',
      proactive_pix_polling_enabled: false
    )
  end

  def create_reservation(unit:, status: :pending_payment, payment_status: 'pending')
    Captain::Reservation.create!(
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      conversation: conversation,
      captain_brand_id: brand.id,
      captain_unit_id: unit.id,
      suite_identifier: "Suite-#{SecureRandom.hex(2)}",
      check_in_at: 1.day.from_now.beginning_of_hour,
      check_out_at: 2.days.from_now.beginning_of_hour,
      status: status,
      payment_status: payment_status,
      total_amount: 100
    )
  end

  def create_charge(reservation:, unit:, created_at: Time.current)
    Captain::PixCharge.create!(
      reservation: reservation,
      unit: unit,
      txid: "txid-#{SecureRandom.hex(8)}",
      status: 'active',
      created_at: created_at,
      updated_at: created_at
    )
  end

  before do
    clear_enqueued_jobs
  end

  it 'enqueues polling only for eligible recent pending charges' do
    eligible_reservation = create_reservation(unit: eligible_unit)
    eligible_charge = create_charge(
      reservation: eligible_reservation,
      unit: eligible_unit,
      created_at: 20.minutes.ago
    )

    old_charge = create_charge(
      reservation: eligible_reservation,
      unit: eligible_unit,
      created_at: 3.hours.ago
    )

    disabled_unit_reservation = create_reservation(unit: ineligible_unit)
    disabled_unit_charge = create_charge(
      reservation: disabled_unit_reservation,
      unit: ineligible_unit,
      created_at: 10.minutes.ago
    )

    scheduled_reservation = create_reservation(unit: eligible_unit, status: :scheduled)
    scheduled_charge = create_charge(
      reservation: scheduled_reservation,
      unit: eligible_unit,
      created_at: 10.minutes.ago
    )

    paid_reservation = create_reservation(unit: eligible_unit, payment_status: 'paid')
    paid_charge = create_charge(
      reservation: paid_reservation,
      unit: eligible_unit,
      created_at: 10.minutes.ago
    )

    described_class.perform_now

    matching_jobs = enqueued_jobs.select do |job|
      job[:job] == Captain::Payments::PollPixChargeStatusJob
    end
    enqueued_ids = matching_jobs.map { |job| job[:args].first }

    expect(enqueued_ids).to include(eligible_charge.id)
    expect(enqueued_ids).not_to include(old_charge.id)
    expect(enqueued_ids).not_to include(disabled_unit_charge.id)
    expect(enqueued_ids).not_to include(scheduled_charge.id)
    expect(enqueued_ids).not_to include(paid_charge.id)
  end
end
