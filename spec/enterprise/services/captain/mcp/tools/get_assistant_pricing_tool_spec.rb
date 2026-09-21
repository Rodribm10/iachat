# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Mcp::Tools::GetAssistantPricingTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:unit) { create(:captain_unit, account: account, name: 'Qnn01') }
  let(:tool) { described_class.new }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox, captain_unit: unit)

    category = Captain::PricingCategory.create!(captain_unit: unit, key: 'standard', aliases: [])
    Captain::PricingAmount.create!(
      pricing_category: category,
      period: 'pernoite_promo',
      day_bucket: 'mon_wed',
      amount: 100
    )
  end

  it 'usa o assistente do contexto quando a cotação não informa assistant_id' do
    result = tool.call({}, context: { account_id: account.id, inbox_id: inbox.id })

    expect(result[:isError]).to be(false)
    expect(result[:content].first[:text]).to include('# Tabela de preços — Qnn01')
    expect(result[:content].first[:text]).to include('| pernoite_promo | R$ 100.0 |')
  end

  it 'informa erro quando não há assistente no contexto' do
    result = tool.call({}, context: {})

    expect(result[:isError]).to be(true)
    expect(result[:content].first[:text]).to eq('Assistente não encontrado no contexto MCP.')
  end
end
