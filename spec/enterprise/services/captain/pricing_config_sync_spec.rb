require 'rails_helper'

RSpec.describe Captain::PricingConfigSync do
  let(:account) { create(:account) }
  let(:unit) { create(:captain_unit, account: account, name: 'Samambaia') }
  let(:config) do
    {
      'profiles' => {
        'camila_samambaia' => {
          'categories' => {
            'standard' => {
              'aliases' => %w[standard comum],
              'amounts' => {
                'pernoite_promo' => { 'mon_wed' => 100, 'thu_sun' => 150 },
                'diaria' => 170
              }
            }
          }
        }
      }
    }
  end

  before do
    create(
      :captain_assistant,
      account: account,
      captain_unit: unit,
      engine: 'hermes',
      hermes_profile_name: 'camila_samambaia',
      hermes_webhook_base_url: 'http://hermes.test'
    )
  end

  it 'sincroniza a tabela pelo profile sem depender de ids de producao' do
    result = described_class.new(config: config).call

    category = unit.pricing_categories.find_by!(key: 'standard')
    expect(result).to include(profiles: 1, categories: 1, amounts: 3, skipped: [])
    expect(category.aliases).to eq(%w[standard comum])
    expect(category.amounts.pluck(:period, :day_bucket, :amount)).to contain_exactly(
      ['pernoite_promo', 'mon_wed', 100.to_d],
      ['pernoite_promo', 'thu_sun', 150.to_d],
      ['diaria', nil, 170.to_d]
    )
  end

  it 'e idempotente e atualiza valor sem duplicar linhas' do
    described_class.new(config: config).call
    config['profiles']['camila_samambaia']['categories']['standard']['amounts']['diaria'] = 180

    expect { described_class.new(config: config).call }
      .not_to change(Captain::PricingAmount, :count)
    expect(unit.pricing_categories.find_by!(key: 'standard').amounts.find_by!(period: 'diaria').amount).to eq(180)
  end
end
