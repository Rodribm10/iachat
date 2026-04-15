# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Concerns::Agentable, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:unit) do
    Captain::Unit.create!(
      account: account,
      brand: brand,
      name: 'Prime Águas Lindas',
      concierge_config: {
        'persona_name' => 'Sofia',
        'knowledge' => 'Hotel com café às 7h',
        'variables' => { 'wifi_password' => 'abc123' }
      }
    )
  end
  let(:contact) { create(:contact, account: account, name: 'João Silva') }
  let(:conversation) do
    create(:conversation,
           account: account, inbox: inbox, contact: contact,
           custom_attributes: { 'current_unit_id' => unit.id })
  end
  let(:assistant) do
    create(:captain_assistant,
           account: account,
           orchestrator_prompt: '{{ concierge.persona_name }} in {{ concierge.unit_name }} knows: {{ concierge.knowledge }}')
  end

  def mock_context_for(conv)
    state = { conversation: { id: conv.id } }.with_indifferent_access
    ctx = instance_double(Agents::RunContext)
    allow(ctx).to receive(:context).and_return({ state: state })
    ctx
  end

  describe '#agent_instructions concierge injection' do
    it 'resolves concierge context from current_unit_id' do
      ctx = mock_context_for(conversation)
      rendered = assistant.agent_instructions(ctx)
      expect(rendered).to include('Sofia in Prime Águas Lindas')
      expect(rendered).to include('Hotel com café às 7h')
    end

    it 'falls back to empty strings when current_unit_id missing' do
      conversation.update!(custom_attributes: {})
      ctx = mock_context_for(conversation)
      rendered = assistant.agent_instructions(ctx)
      expect(rendered).to be_a(String)
    end

    it 'falls back gracefully when conversation id is nil' do
      state = { conversation: {} }.with_indifferent_access
      ctx = instance_double(Agents::RunContext)
      allow(ctx).to receive(:context).and_return({ state: state })
      rendered = assistant.agent_instructions(ctx)
      expect(rendered).to be_a(String)
    end
  end
end
