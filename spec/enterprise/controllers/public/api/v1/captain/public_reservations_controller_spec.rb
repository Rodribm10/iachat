# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public Captain Reservations API', type: :request do
  let(:valid_token) { 'test-token-abc' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:unit) do
    Captain::Unit.create!(account: account, brand: brand, inbox_id: inbox.id,
                          name: 'Hotel Teste', inter_pix_key: 'pix@test.com',
                          inter_account_number: '12345678')
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RESERVA_1001_API_TOKEN', any_args).and_return(valid_token)
  end

  describe 'POST /public/api/v1/captain/public_reservations' do
    context 'without token' do
      it 'returns 401' do
        post '/public/api/v1/captain/public_reservations',
             params: { chatwoot_unit_id: unit.id }.to_json,
             headers: { 'Content-Type' => 'application/json' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid token' do
      it 'returns 401' do
        post '/public/api/v1/captain/public_reservations',
             params: { chatwoot_unit_id: unit.id }.to_json,
             headers: {
               'Content-Type' => 'application/json',
               'X-Reserva-Token' => 'wrong'
             }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with valid token and valid payload' do
      let(:unit) do
        Captain::Unit.create!(
          account: account, brand: brand, inbox_id: inbox.id,
          name: 'Hotel Teste Com Inter', inter_pix_key: 'fake-key@test.com',
          inter_account_number: '1234567', inter_client_id: 'fake-id',
          inter_client_secret: 'fake-secret', inter_cert_content: 'FAKE-CERT',
          inter_key_content: 'FAKE-KEY'
        )
      end

      let(:valid_payload) do
        {
          chatwoot_unit_id: unit.id,
          category: 'Standard',
          stay_type: '3hrs',
          checkin_at: 2.hours.from_now.iso8601,
          customer: {
            name: 'Maria Teste',
            phone: '+5561999990000',
            cpf: '12345678909',
            email: 'maria@teste.com'
          },
          total_cents: 12_000,
          deposit_cents: 6_000,
          notes: 'Chegaremos as 15h'
        }
      end

      let(:fake_pix_charge) do
        instance_double(Captain::PixCharge,
                        id: 99,
                        txid: 'test-txid-123',
                        pix_copia_e_cola: '00020126...',
                        status: 'active')
      end

      before do
        cob_service = instance_double(Captain::Inter::CobService)
        allow(Captain::Inter::CobService).to receive(:new).and_return(cob_service)
        allow(cob_service).to receive(:call).and_return(fake_pix_charge)
      end

      it 'returns 201 with reservation and PIX payload' do
        post '/public/api/v1/captain/public_reservations',
             params: valid_payload.to_json,
             headers: {
               'Content-Type' => 'application/json',
               'X-Reserva-Token' => valid_token
             }

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body['reservation_id']).to be_present
        expect(body['conversation_id']).to be_present
        expect(body['pix']['txid']).to eq('test-txid-123')
        expect(body['pix']['copia_e_cola']).to start_with('00020126')
      end

      it 'creates Contact, Conversation and Reservation' do
        expect do
          post '/public/api/v1/captain/public_reservations',
               params: valid_payload.to_json,
               headers: {
                 'Content-Type' => 'application/json',
                 'X-Reserva-Token' => valid_token
               }
        end.to change(Contact, :count).by(1)
           .and change(Conversation, :count).by(1)
           .and change(Captain::Reservation, :count).by(1)
      end
    end
  end

  describe 'GET /public/api/v1/captain/public_reservations/:id/status' do
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact) }
    let(:reservation) do
      Captain::Reservation.create!(
        account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
        unit: unit, suite_identifier: 'Standard · 3hrs',
        check_in_at: 1.hour.from_now, check_out_at: 4.hours.from_now,
        status: :pending_payment, payment_status: 'pending', total_amount: 120.0
      )
    end

    it 'requires token' do
      get "/public/api/v1/captain/public_reservations/#{reservation.id}/status"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns pending for unpaid reservation' do
      get "/public/api/v1/captain/public_reservations/#{reservation.id}/status",
          headers: { 'X-Reserva-Token' => valid_token }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['status']).to eq('pending')
    end

    it 'returns paid after payment_status flips' do
      reservation.update!(payment_status: 'paid')
      get "/public/api/v1/captain/public_reservations/#{reservation.id}/status",
          headers: { 'X-Reserva-Token' => valid_token }
      expect(JSON.parse(response.body)['status']).to eq('paid')
    end

    it 'returns 404 for unknown reservation' do
      get '/public/api/v1/captain/public_reservations/999999/status',
          headers: { 'X-Reserva-Token' => valid_token }
      expect(response).to have_http_status(:not_found)
    end
  end
end
