# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Payments::PollPixChargeStatusJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end
  let(:brand) { Captain::Brand.create!(account: account, name: 'Brand Test') }
  let(:unit) do
    Captain::Unit.create!(
      account: account,
      captain_brand_id: brand.id,
      name: 'Unit Prime',
      inter_client_id: 'client-id',
      inter_client_secret: 'client-secret',
      inter_pix_key: '11999999999',
      inter_account_number: '210339349',
      inter_cert_content: 'cert-content',
      inter_key_content: 'key-content',
      proactive_pix_polling_enabled: true
    )
  end
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
      payment_status: 'pending',
      total_amount: 100
    )
  end
  let(:charge) do
    Captain::PixCharge.create!(
      reservation: reservation,
      unit: unit,
      txid: "txid-#{SecureRandom.hex(8)}",
      status: 'active'
    )
  end

  let(:lock_manager) { instance_double(Redis::LockManager) }

  before do
    allow(Redis::LockManager).to receive(:new).and_return(lock_manager)
    allow(lock_manager).to receive(:lock).and_return(true)
    allow(lock_manager).to receive(:unlock).and_return(true)
  end

  it 'marks charge as paid and confirms reservation when Inter reports payment' do
    status_payload = {
      success: true,
      paid: true,
      status: 'CONCLUIDA',
      end_to_end_id: 'E2E123',
      raw_payload: { 'status' => 'CONCLUIDA' }
    }
    status_service = instance_double(Captain::Inter::CobStatusService, call: status_payload)
    allow(Captain::Inter::CobStatusService).to receive(:new).with(charge).and_return(status_service)

    confirmation_service = instance_double(Captain::Payments::ConfirmationService, perform: true)
    allow(Captain::Payments::ConfirmationService).to receive(:new).with(
      reservation: reservation,
      source: 'inter_cob_query_polling',
      payload: status_payload[:raw_payload]
    ).and_return(confirmation_service)

    described_class.perform_now(charge.id)

    charge.reload
    expect(charge.status).to eq('paid')
    expect(charge.e2eid).to eq('E2E123')
    expect(charge.paid_at).to be_present
    expect(confirmation_service).to have_received(:perform)
  end

  it 'keeps charge active when Inter still reports pending payment' do
    status_service = instance_double(
      Captain::Inter::CobStatusService,
      call: { success: true, paid: false, status: 'ATIVA', raw_payload: { 'status' => 'ATIVA' } }
    )
    allow(Captain::Inter::CobStatusService).to receive(:new).with(charge).and_return(status_service)
    allow(Captain::Payments::ConfirmationService).to receive(:new)

    described_class.perform_now(charge.id)

    expect(charge.reload.status).to eq('active')
    expect(Captain::Payments::ConfirmationService).not_to have_received(:new)
  end

  it 'expires charge and removes awaiting payment label when txid is expired' do
    conversation.update_labels(%w[aguardando_pagamento vip])
    charge.update!(created_at: 2.hours.ago, updated_at: 2.hours.ago)

    allow(Captain::Inter::CobStatusService).to receive(:new)

    described_class.perform_now(charge.id)

    expect(charge.reload.status).to eq('expired')
    expect(conversation.reload.label_list).to include('vip')
    expect(conversation.reload.label_list).not_to include('aguardando_pagamento')
    expect(Captain::Inter::CobStatusService).not_to have_received(:new)
  end

  it 'skips polling when unit proactive flag is disabled' do
    unit.update!(proactive_pix_polling_enabled: false)
    allow(Captain::Inter::CobStatusService).to receive(:new)

    described_class.perform_now(charge.id)

    expect(Captain::Inter::CobStatusService).not_to have_received(:new)
    expect(charge.reload.status).to eq('active')
  end
end
