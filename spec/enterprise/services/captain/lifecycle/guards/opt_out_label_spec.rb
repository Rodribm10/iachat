# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::OptOutLabel do
  subject(:guard) { described_class.new(delivery) }

  let(:account) { create(:account) }
  let(:label) { create(:label, account: account, title: 'nao_mandar_auto') }
  let(:contact) { create(:contact, account: account) }
  let(:reservation) { create(:captain_reservation, account: account, contact: contact) }
  let(:delivery) { create(:captain_lifecycle_delivery, account: account, captain_reservation: reservation) }

  context 'when no config' do
    it 'passes' do
      expect(guard.check).to eq(action: :pass)
    end
  end

  context 'with config and opt_out_label configured' do
    before { create(:captain_lifecycle_config, account: account, opt_out_label: label) }

    it 'passes when contact has no opt_out label' do
      expect(guard.check).to eq(action: :pass)
    end

    it 'skips when contact has the configured label' do
      contact.update!(label_list: [label.title])
      expect(guard.check).to eq(action: :skip, reason: 'opt_out_label')
    end
  end
end
