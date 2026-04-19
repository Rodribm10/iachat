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
    expect(runner.send(:build_system_prompt_with_memory, 'Hi there')).to include('<memoria_cliente>')
  end

  it 'skips injection when recall flag is off' do
    account.update!(custom_attributes: {})
    expect(runner.send(:build_system_prompt_with_memory, 'Hi there')).not_to include('<memoria_cliente>')
  end
end
# rubocop:enable RSpec/DescribeClass
