# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Mcp::Server do
  let(:assistant) do
    create(:captain_assistant, config: { 'mcp_tool_allowlist' => ['handoff'] })
  end
  let(:context) { { account_id: assistant.account_id, assistant_id: assistant.id } }

  it 'aplica a política do assistente no tools/list' do
    response = described_class.handle(
      { 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'tools/list', 'params' => {} },
      context: context
    )

    expect(response.dig(:result, :tools).pluck(:name)).to eq(['handoff'])
  end

  it 'devolve erro de protocolo ao tentar executar uma ferramenta bloqueada' do
    response = described_class.handle(
      {
        'jsonrpc' => '2.0',
        'id' => 2,
        'method' => 'tools/call',
        'params' => { 'name' => 'generate_pix', 'arguments' => {} }
      },
      context: context
    )

    expect(response).to include(
      jsonrpc: '2.0',
      id: 2,
      error: { code: -32_602, message: 'Tool indisponível: generate_pix' }
    )
  end
end
