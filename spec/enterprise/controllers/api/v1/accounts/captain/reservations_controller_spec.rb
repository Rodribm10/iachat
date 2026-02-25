require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::Reservations', type: :request do
  around do |example|
    original = Rails.application.env_config['action_dispatch.show_exceptions']
    Rails.application.env_config['action_dispatch.show_exceptions'] = :none
    example.run
  ensure
    Rails.application.env_config['action_dispatch.show_exceptions'] = original
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Rodrigo Borba', phone_number: '+5511999990001') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:brand) { Captain::Brand.create!(account: account, name: 'Brand Test') }
  let(:unit) { Captain::Unit.create!(account: account, captain_brand_id: brand.id, name: 'Matriz') }

  def json_response
    JSON.parse(response.body)
  end

  def create_reservation(attrs = {})
    Captain::Reservation.create!(
      {
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        conversation: conversation,
        captain_brand_id: brand.id,
        captain_unit_id: unit.id,
        suite_identifier: 'Suite 101',
        check_in_at: 2.days.from_now.beginning_of_day,
        check_out_at: 3.days.from_now.beginning_of_day,
        total_amount: 130,
        metadata: { deposit_amount: 65 },
        status: :pending_payment
      }.merge(attrs)
    )
  end

  describe 'GET /api/v1/accounts/:account_id/captain/reservations' do
    let!(:pending_reservation) do
      create_reservation(
        suite_identifier: 'Suite Pendente',
        check_in_at: Time.zone.parse('2026-02-25 12:00:00'),
        check_out_at: Time.zone.parse('2026-02-26 12:00:00'),
        status: :pending_payment
      )
    end
    let!(:confirmed_reservation) do
      create_reservation(
        suite_identifier: 'Suite Confirmada',
        check_in_at: Time.zone.parse('2026-02-28 12:00:00'),
        check_out_at: Time.zone.parse('2026-03-01 12:00:00'),
        status: :scheduled,
        metadata: {},
        total_amount: 210
      )
    end

    it 'returns paginated reservations ordered by operational priority by default' do
      get "/api/v1/accounts/#{account.id}/captain/reservations",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response['payload'].pluck('id')).to eq([pending_reservation.id, confirmed_reservation.id])
      expect(json_response.dig('meta', 'total_count')).to eq(2)
      expect(json_response.dig('payload', 0, 'ui_status')).to eq('pending_payment')
    end

    it 'filters by confirmed ui status and search query' do
      contact.update!(custom_attributes: { cpf: '002.519.381-31' })

      get "/api/v1/accounts/#{account.id}/captain/reservations",
          params: { status: 'confirmed', q: '002.519' },
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response['payload'].size).to eq(1)
      expect(json_response.dig('payload', 0, 'id')).to eq(confirmed_reservation.id)
    end

    it 'supports combined date range and unit filters' do
      other_unit = Captain::Unit.create!(
        account: account,
        captain_brand_id: brand.id,
        name: 'Filial'
      )
      create_reservation(
        suite_identifier: 'Outra unidade',
        captain_unit_id: other_unit.id,
        check_in_at: Time.zone.parse('2026-02-25 16:00:00'),
        check_out_at: Time.zone.parse('2026-02-26 10:00:00')
      )

      get "/api/v1/accounts/#{account.id}/captain/reservations",
          params: {
            unit_id: unit.id,
            date_from: '2026-02-24',
            date_to: '2026-02-26'
          },
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response['payload'].pluck('id')).to eq([pending_reservation.id])
    end
  end

  describe 'GET /api/v1/accounts/:account_id/captain/reservations/revenue' do
    let!(:unit_two) do
      Captain::Unit.create!(
        account: account,
        captain_brand_id: brand.id,
        name: 'Filial'
      )
    end

    let!(:pending_reservation) do
      create_reservation(
        suite_identifier: 'Suite Pendente',
        status: :pending_payment,
        total_amount: 400
      )
    end

    before do
      create_reservation(
        suite_identifier: 'Suite Alfa',
        status: :scheduled,
        total_amount: 200,
        check_in_at: Time.zone.parse('2026-02-25 10:00:00'),
        check_out_at: Time.zone.parse('2026-02-26 10:00:00')
      )

      create_reservation(
        suite_identifier: 'Suite Alfa',
        status: :active,
        total_amount: 100,
        check_in_at: Time.zone.parse('2026-02-25 18:00:00'),
        check_out_at: Time.zone.parse('2026-02-26 12:00:00')
      )

      create_reservation(
        suite_identifier: 'Suite Beta',
        captain_unit_id: unit_two.id,
        status: :completed,
        total_amount: 80,
        check_in_at: Time.zone.parse('2026-02-27 10:00:00'),
        check_out_at: Time.zone.parse('2026-02-28 10:00:00')
      )
    end

    it 'returns revenue summary considering only confirmed reservations' do
      get "/api/v1/accounts/#{account.id}/captain/reservations/revenue",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response.dig('summary', 'confirmed_count')).to eq(3)
      expect(json_response.dig('summary', 'total_revenue')).to eq(380.0)
      expect(json_response.dig('summary', 'average_ticket')).to be_within(0.001).of(126.666)

      expect(json_response['by_unit'].size).to eq(2)

      suite_alfa = json_response['by_suite'].find { |item| item['suite_identifier'] == 'Suite Alfa' }
      expect(suite_alfa['reservations_count']).to eq(2)
      expect(suite_alfa['total_revenue']).to eq(300.0)
    end

    it 'supports filters by unit, date range and suite identifier' do
      get "/api/v1/accounts/#{account.id}/captain/reservations/revenue",
          params: {
            unit_id: unit.id,
            suite: 'alfa',
            date_from: '2026-02-25',
            date_to: '2026-02-25'
          },
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response.dig('summary', 'confirmed_count')).to eq(2)
      expect(json_response.dig('summary', 'total_revenue')).to eq(300.0)
      expect(json_response['by_unit'].size).to eq(1)
      expect(json_response['by_suite'].size).to eq(1)
      expect(json_response.dig('by_suite', 0, 'suite_identifier')).to eq('Suite Alfa')
    end

    it 'does not include pending reservations in revenue totals' do
      get "/api/v1/accounts/#{account.id}/captain/reservations/revenue",
          params: { suite: 'pendente' },
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response.dig('summary', 'confirmed_count')).to eq(0)
      expect(json_response.dig('summary', 'total_revenue')).to eq(0.0)
      expect(json_response['by_unit']).to eq([])
      expect(json_response['by_suite']).to eq([])
      expect(pending_reservation.total_amount.to_f).to eq(400.0)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/captain/reservations/:id/pix' do
    it 'returns reason not_generated when there is no active charge' do
      reservation = create_reservation

      get "/api/v1/accounts/#{account.id}/captain/reservations/#{reservation.id}/pix",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response['pix_copy_paste']).to be_nil
      expect(json_response['reason']).to eq('not_generated')
    end

    it 'returns expired when pending payment pix charge is stale' do
      reservation = create_reservation
      Captain::PixCharge.create!(
        reservation: reservation,
        unit: unit,
        txid: SecureRandom.hex(8),
        status: 'active',
        created_at: 2.hours.ago,
        updated_at: 2.hours.ago
      )

      get "/api/v1/accounts/#{account.id}/captain/reservations/#{reservation.id}/pix",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(json_response['pix_copy_paste']).to be_nil
      expect(json_response['reason']).to eq('expired')
    end
  end
end
