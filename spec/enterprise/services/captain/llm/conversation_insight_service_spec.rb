require 'rails_helper'

RSpec.describe Captain::Llm::ConversationInsightService do
  describe '#build_chunks' do
    it 'formats only messages inside the requested period' do
      account = create(:account)
      inbox = create(:inbox, account: account)
      period_start = Date.new(2026, 5, 17)
      conversation = create(:conversation, account: account, inbox: inbox)

      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'mensagem antiga',
                       created_at: period_start.prev_day.noon)
      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'mensagem do periodo',
                       created_at: period_start.noon)

      service = described_class.new(
        account: account,
        inbox: inbox,
        conversations: [conversation],
        period_start: period_start,
        period_end: period_start
      )

      text = service.send(:build_chunks).join("\n")

      expect(text).to include('mensagem do periodo')
      expect(text).not_to include('mensagem antiga')
    end
  end
end
