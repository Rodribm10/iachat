# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Inter::CobStatusService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
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
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      conversation: conversation,
      captain_brand_id: brand.id,
      captain_unit_id: unit.id,
      suite_identifier: 'Suite 101',
      check_in_at: 1.day.from_now.change(hour: 19, min: 0, sec: 0),
      check_out_at: 2.days.from_now.change(hour: 12, min: 0, sec: 0),
      status: :pending_payment,
      payment_status: 'pending',
      total_amount: 200
    )
  end
  let(:charge) do
    Captain::PixCharge.create!(
      reservation: reservation,
      unit: unit,
      txid: "txid-#{SecureRandom.hex(6)}",
      status: 'active'
    )
  end
  let(:service) { described_class.new(charge) }
  let(:auth_service) { instance_double(Captain::Inter::AuthService, token: 'inter-token') }
  let(:connection) { instance_double(Faraday::Connection) }

  before do
    allow(Captain::Inter::AuthService).to receive(:new).with(unit).and_return(auth_service)
    allow(service).to receive(:connection).with('inter-token').and_return(connection)
  end

  it 'returns paid=true when Inter status is CONCLUIDA' do
    response_body = {
      txid: charge.txid,
      status: 'CONCLUIDA',
      pix: [{ endToEndId: 'E2E123', valor: '2.50' }]
    }.to_json
    response = instance_double(Faraday::Response, success?: true, status: 200, body: response_body)
    allow(connection).to receive(:get).and_return(response)

    result = service.call

    expect(result[:success]).to be(true)
    expect(result[:paid]).to be(true)
    expect(result[:status]).to eq('CONCLUIDA')
    expect(result[:end_to_end_id]).to eq('E2E123')
  end

  it 'returns paid=false when Inter status is ATIVA and no pix payment entry exists' do
    response_body = {
      txid: charge.txid,
      status: 'ATIVA',
      pix: []
    }.to_json
    response = instance_double(Faraday::Response, success?: true, status: 200, body: response_body)
    allow(connection).to receive(:get).and_return(response)

    result = service.call

    expect(result[:success]).to be(true)
    expect(result[:paid]).to be(false)
    expect(result[:status]).to eq('ATIVA')
  end

  it 'raises descriptive error when Inter returns non-success response' do
    response = instance_double(Faraday::Response, success?: false, status: 404, body: '{"title":"not_found"}')
    allow(connection).to receive(:get).and_return(response)

    expect { service.call }.to raise_error(/Pix Status Check Failed: HTTP 404/)
  end
end
