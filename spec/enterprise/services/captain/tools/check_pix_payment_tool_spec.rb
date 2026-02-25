# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Tools::CheckPixPaymentTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:brand) { Captain::Brand.create!(account: account, name: 'Brand Test') }
  let(:unit) do
    Captain::Unit.create!(
      account: account,
      captain_brand_id: brand.id,
      name: 'Matriz',
      inter_client_id: 'client-id',
      inter_client_secret: 'client-secret',
      inter_pix_key: '11999999999',
      inter_cert_content: 'fake-cert',
      inter_key_content: 'fake-key'
    )
  end
  let(:reservation) do
    Captain::Reservation.create!(
      account: account,
      inbox: conversation.inbox,
      contact: conversation.contact,
      contact_inbox: conversation.contact_inbox,
      conversation: conversation,
      captain_brand_id: brand.id,
      captain_unit_id: unit.id,
      suite_identifier: 'Suite 101',
      check_in_at: 1.day.from_now.change(hour: 19, min: 0, sec: 0),
      check_out_at: 2.days.from_now.change(hour: 12, min: 0, sec: 0),
      status: :pending_payment,
      payment_status: 'pending',
      total_amount: 220
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
  let(:tool_context) do
    Struct.new(:state).new(
      {
        account_id: account.id,
        conversation: { id: conversation.id }
      }
    )
  end

  it 'returns pending message when Inter still reports unpaid charge' do
    status_service = instance_double(Captain::Inter::CobStatusService, call: { success: true, paid: false, status: 'ATIVA' })
    allow(Captain::Inter::CobStatusService).to receive(:new).with(charge).and_return(status_service)
    charge

    result = tool.execute(tool_context)

    expect(result[:success]).to be(true)
    expect(result[:formatted_message]).to match(/ainda não apareceu como pago/i)
    expect(charge.reload.status).to eq('active')
  end

  it 'marks charge as paid and confirms reservation when Inter reports payment' do
    charge
    status_service = instance_double(
      Captain::Inter::CobStatusService,
      call: {
        success: true,
        paid: true,
        status: 'CONCLUIDA',
        end_to_end_id: 'E2E123',
        paid_value: '2.50',
        raw_payload: { 'txid' => charge.txid, 'status' => 'CONCLUIDA' }
      }
    )
    allow(Captain::Inter::CobStatusService).to receive(:new).with(charge).and_return(status_service)

    confirmation_service = instance_double(Captain::Payments::ConfirmationService, perform: true)
    allow(Captain::Payments::ConfirmationService).to receive(:new).with(
      reservation: reservation,
      source: 'inter_cob_query',
      payload: { 'txid' => charge.txid, 'status' => 'CONCLUIDA' }
    ).and_return(confirmation_service)

    result = tool.execute(tool_context, txid: charge.txid)

    expect(result[:success]).to be(true)
    expect(result[:formatted_message]).to match(/pagamento confirmado no banco inter/i)

    charge.reload
    expect(charge.status).to eq('paid')
    expect(charge.e2eid).to eq('E2E123')
    expect(charge.paid_at).to be_present
    expect(confirmation_service).to have_received(:perform)
  end

  it 'does not query Inter again when charge is already paid' do
    charge.update!(status: 'paid', paid_at: Time.current)
    expect(Captain::Inter::CobStatusService).not_to receive(:new)

    result = tool.execute(tool_context, txid: charge.txid)

    expect(result[:success]).to be(true)
    expect(result[:formatted_message]).to match(/pagamento já confirmado/i)
  end

  it 'returns a friendly message when there is no pix charge in the conversation' do
    result = tool.execute(tool_context)

    expect(result[:success]).to be(true)
    expect(result[:formatted_message]).to match(/não encontrei uma cobrança pix/i)
  end

  it 'returns integration credential guidance on auth failure' do
    charge
    status_service = instance_double(Captain::Inter::CobStatusService)
    allow(Captain::Inter::CobStatusService).to receive(:new).with(charge).and_return(status_service)
    allow(status_service).to receive(:call).and_raise(StandardError, 'Login/senha invalido')

    result = tool.execute(tool_context)

    expect(result[:success]).to be(true)
    expect(result[:formatted_message]).to match(/credenciais da integração estão inválidas/i)
  end
end
