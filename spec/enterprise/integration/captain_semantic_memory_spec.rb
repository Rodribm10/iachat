require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Captain semantic memory integration' do
  let(:account) { create(:account, custom_attributes: attrs) }
  let(:attrs) { { 'captain_contact_memory_recall_enabled' => true } }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:runner) { Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: conversation) }

  before do
    create(:captain_contact_memory, account: account, contact: contact, content: 'Prefere Stilo', embedding: Array.new(1536, 0.1))
    allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(
      instance_double(Captain::Llm::EmbeddingService, get_embedding: Array.new(1536, 0.1))
    )
  end

  it 'injects <memoria_cliente> block into system prompt when recall flag is on' do
    result = runner.send(:build_system_prompt_with_memory, 'Hi there', 'base_system_prompt')
    expect(result).to include('<memoria_cliente>')
    expect(result).to include('base_system_prompt')
  end

  it 'skips injection when recall flag is off' do
    account.update!(custom_attributes: {})
    result = runner.send(:build_system_prompt_with_memory, 'Hi there', 'base_system_prompt')
    expect(result).not_to include('<memoria_cliente>')
    expect(result).to eq('base_system_prompt')
  end

  describe 'end-to-end learning and recall' do
    let(:attrs) do
      {
        'captain_contact_memory_extraction_enabled' => true,
        'captain_contact_memory_recall_enabled' => true
      }
    end

    it 'learns from a resolved conversation and recalls in a new one' do
      # 1. Old conversation — learning phase
      old_conv = create(:conversation, account: account, contact: contact)
      create(:message, conversation: old_conv, message_type: :incoming, content: 'quero sempre a Stilo com hidro')
      create(:message, conversation: old_conv, message_type: :outgoing, content: 'combinado')

      allow_any_instance_of(Captain::ContactMemories::ExtractionService).to receive(:call).and_return( # rubocop:disable RSpec/AnyInstance
        [
          {
            memory_type: 'preferencia',
            content: 'Prefere Stilo com hidro',
            evidence: 'disse quero sempre a Stilo',
            confidence: 0.95,
            scope: 'global'
          }
        ]
      )

      # Simulate conversation.resolved → extraction job
      Captain::ContactMemories::ExtractFromConversationJob.perform_now(old_conv.id)

      # Simulate embedding job completing (UpdateEmbeddingJob was enqueued but not run here)
      last_memory = Captain::ContactMemory.where(content: 'Prefere Stilo com hidro').last
      last_memory.update!(embedding: Array.new(1536, 0.1))

      # 2. New conversation — recall phase
      new_conv = create(:conversation, account: account, contact: contact)
      new_runner = Captain::Assistant::AgentRunnerService.new(assistant: assistant, conversation: new_conv)

      result = new_runner.send(:build_system_prompt_with_memory, 'oi, quero reservar', 'base_system_prompt')
      expect(result).to include('Prefere Stilo com hidro')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
