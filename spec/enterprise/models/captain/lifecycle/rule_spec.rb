# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Rule, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by_user).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:captain_lifecycle_rule) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:event) }
    it { is_expected.to validate_presence_of(:message_body) }
    it { is_expected.to validate_inclusion_of(:event).in_array(Captain::Lifecycle::Rule::EVENTS) }
    it { is_expected.to validate_inclusion_of(:message_type).in_array(%w[text buttons list url_button]) }
  end

  describe '.active' do
    it 'returns only enabled rules' do
      enabled = create(:captain_lifecycle_rule, enabled: true)
      create(:captain_lifecycle_rule, enabled: false)
      expect(described_class.active).to contain_exactly(enabled)
    end
  end

  describe '.for_event' do
    it 'filters by event' do
      rule = create(:captain_lifecycle_rule, event: 'checkin.scheduled_at')
      create(:captain_lifecycle_rule, event: 'reservation.confirmed')
      expect(described_class.for_event('checkin.scheduled_at')).to contain_exactly(rule)
    end
  end

  describe '#matches_reservation?' do
    let(:account) { create(:account) }
    let(:brand) { Captain::Brand.create!(account: account, name: 'Brand Test') }
    let(:unit) { Captain::Unit.create!(account: account, captain_brand_id: brand.id, name: 'Águas Lindas') }
    let(:reservation) do
      create(:captain_reservation,
             account: account,
             unit: unit,
             suite_identifier: 'Alexa',
             metadata: { 'permanencia' => 'Pernoite' })
    end

    it 'matches when all filters empty' do
      rule = build(:captain_lifecycle_rule, account: account, filters: {})
      expect(rule.matches_reservation?(reservation)).to be(true)
    end

    it 'matches when unit_id in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'unit_ids' => [unit.id] })
      expect(rule.matches_reservation?(reservation)).to be(true)
    end

    it 'does not match when unit_id not in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'unit_ids' => [999] })
      expect(rule.matches_reservation?(reservation)).to be(false)
    end

    it 'matches when categoria in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'categorias' => ['Alexa'] })
      expect(rule.matches_reservation?(reservation)).to be(true)
    end

    it 'does not match when categoria not in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'categorias' => ['Stilo'] })
      expect(rule.matches_reservation?(reservation)).to be(false)
    end

    it 'matches when permanencia in filter' do
      rule = build(:captain_lifecycle_rule, account: account, filters: { 'permanencias' => ['Pernoite'] })
      expect(rule.matches_reservation?(reservation)).to be(true)
    end

    it 'requires all specified filters to match' do
      rule = build(:captain_lifecycle_rule, account: account,
                                            filters: { 'unit_ids' => [unit.id], 'categorias' => ['Stilo'] })
      expect(rule.matches_reservation?(reservation)).to be(false)
    end
  end
end
