# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Mcp::Tools::FaqLookupTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:context) { { account_id: account.id, assistant_id: assistant.id } }
  let(:tool) { described_class.new }

  it 'usa a tabela oficial quando a pergunta é de preço' do
    pricing_result = { content: [{ type: 'text', text: 'Tabela oficial' }], isError: false }
    pricing_tool = instance_double(Captain::Mcp::Tools::GetAssistantPricingTool, call: pricing_result)

    allow(Captain::Mcp::Tools::GetAssistantPricingTool).to receive(:new).and_return(pricing_tool)

    result = tool.call({ 'query' => 'Qual valor da pernoite hoje?' }, context: context)

    expect(result).to eq(pricing_result)
    expect(pricing_tool).to have_received(:call).with({}, context: context)
  end

  it 'mantém FAQ para perguntas que não são de cotação' do
    search = instance_double(Captain::Tools::SearchReplyDocumentationService, execute: 'Aceitamos pets.')
    allow(Captain::Tools::SearchReplyDocumentationService).to receive(:new).and_return(search)

    result = tool.call({ 'query' => 'Vocês aceitam pets?' }, context: context)

    expect(result[:isError]).to be(false)
    expect(result[:content].first[:text]).to eq('Aceitamos pets.')
  end
end
