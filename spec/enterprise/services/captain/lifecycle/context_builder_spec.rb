# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::ContextBuilder do
  let(:account) { create(:account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:unit) do
    Captain::Unit.create!(
      account: account,
      brand: brand,
      name: 'Águas Lindas',
      concierge_config: {
        'persona_name' => 'Sofia',
        'variables' => { 'wifi_password' => 'hotel1001', 'menu_link' => 'https://menu.x' }
      }
    )
  end
  let(:contact) { create(:contact, account: account, name: 'João Silva', phone_number: '+5561999999999') }
  let(:reservation) do
    create(:captain_reservation,
           account: account,
           unit: unit,
           contact: contact,
           suite_identifier: 'Alexa',
           total_amount: 160.0,
           check_in_at: Time.zone.parse('2026-04-20 22:00:00'),
           check_out_at: Time.zone.parse('2026-04-21 12:00:00'),
           metadata: { 'permanencia' => 'Pernoite' })
  end

  describe '.build' do
    subject(:ctx) { described_class.build(reservation) }

    it 'includes customer.name and first_name' do
      expect(ctx['customer']['name']).to eq('João Silva')
      expect(ctx['customer']['first_name']).to eq('João')
    end

    it 'includes customer.phone' do
      expect(ctx['customer']['phone']).to eq('+5561999999999')
    end

    it 'includes reservation.suite' do
      expect(ctx['reservation']['suite']).to eq('Alexa')
    end

    it 'includes reservation.unit_name' do
      expect(ctx['reservation']['unit_name']).to eq('Águas Lindas')
    end

    it 'formats reservation.amount as BRL' do
      expect(ctx['reservation']['amount']).to include('R$')
      expect(ctx['reservation']['amount']).to include('160')
    end

    it 'includes reservation.permanencia' do
      expect(ctx['reservation']['permanencia']).to eq('Pernoite')
    end

    it 'includes hotel.wifi_password from unit variables' do
      expect(ctx['hotel']['wifi_password']).to eq('hotel1001')
    end

    it 'includes hotel.menu_link from unit variables' do
      expect(ctx['hotel']['menu_link']).to eq('https://menu.x')
    end
  end
end
