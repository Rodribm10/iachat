# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Mcp::ToolRegistry do
  let(:assistant) do
    create(:captain_assistant, config: { 'mcp_tool_allowlist' => %w[add_label handoff] })
  end
  let(:context) { { account_id: assistant.account_id, assistant_id: assistant.id } }

  describe '.descriptors' do
    it 'expõe somente os descritores permitidos para o assistente' do
      names = described_class.descriptors(context: context).pluck(:name)

      expect(names).to contain_exactly('add_label', 'handoff')
    end

    it 'preserva todos os descritores nas chamadas legadas sem identidade' do
      expect(described_class.descriptors.size).to eq(described_class::TOOLS.size)
    end
  end

  describe '.call' do
    it 'bloqueia uma ferramenta registrada que não pertence ao allowlist' do
      expect do
        described_class.call('generate_pix', {}, context: context)
      end.to raise_error(described_class::ToolNotAllowedError, 'Tool indisponível: generate_pix')
    end

    it 'distingue ferramenta inexistente de ferramenta bloqueada' do
      expect do
        described_class.call('ferramenta_inexistente', {}, context: context)
      end.to raise_error(described_class::ToolNotFoundError, 'Tool não registrada: ferramenta_inexistente')
    end
  end
end
