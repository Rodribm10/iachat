# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Mcp::ToolPolicy do
  let(:registered_tool_names) { %w[add_label generate_pix handoff] }

  def policy(context)
    described_class.new(context: context, registered_tool_names: registered_tool_names)
  end

  it 'mantém todas as ferramentas quando o contexto não identifica um assistente' do
    expect(policy(account_id: 1).allowed_tool_names).to eq(registered_tool_names)
  end

  it 'mantém todas as ferramentas para um assistente legado sem allowlist' do
    assistant = create(:captain_assistant, config: {})

    expect(policy(assistant_id: assistant.id).allowed_tool_names).to eq(registered_tool_names)
  end

  it 'libera somente ferramentas registradas presentes no allowlist' do
    assistant = create(
      :captain_assistant,
      config: { 'mcp_tool_allowlist' => %w[handoff desconhecida add_label] }
    )

    expect(policy(assistant_id: assistant.id).allowed_tool_names).to contain_exactly('add_label', 'handoff')
  end

  it 'aceita allowlist vazio para um assistente sem ferramentas' do
    assistant = create(:captain_assistant, config: { 'mcp_tool_allowlist' => [] })

    expect(policy(assistant_id: assistant.id).allowed_tool_names).to be_empty
  end

  it 'resolve o assistente pelo inbox quando assistant_id não é informado' do
    captain_inbox = create(:captain_inbox)
    captain_inbox.captain_assistant.update!(mcp_tool_allowlist: ['handoff'])

    result = policy(
      inbox_id: captain_inbox.inbox_id,
      account_id: captain_inbox.captain_assistant.account_id
    ).allowed_tool_names

    expect(result).to eq(['handoff'])
  end

  it 'não libera ferramentas quando a identidade informada é inválida' do
    expect(policy(assistant_id: 0).allowed_tool_names).to be_empty
  end

  it 'não libera ferramentas quando o assistente não pertence à conta informada' do
    assistant = create(:captain_assistant)
    other_account = create(:account)

    result = policy(assistant_id: assistant.id, account_id: other_account.id).allowed_tool_names

    expect(result).to be_empty
  end
end
