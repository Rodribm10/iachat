require 'rails_helper'

RSpec.describe Captain::Reports::GenerateInsightsJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:period_start) { Date.new(2026, 5, 17) }
  let(:period_end) { Date.new(2026, 5, 17) }
  let(:payload) do
    {
      'top_topics' => [],
      'ai_failures' => [],
      'faq_gaps' => [],
      'sentiment' => { 'positive_count' => 0, 'negative_count' => 0, 'neutral_count' => 0, 'summary' => '' },
      'highlights' => { 'praises' => [], 'complaints' => [] },
      'most_requested_suites' => [],
      'price_reactions' => { 'summary' => '', 'objections_count' => 0 },
      'customer_opportunities' => [],
      'recommendations' => [],
      'period_summary' => 'Resumo do dia.'
    }
  end

  it 'analyzes conversations with messages in the requested period and counts only period messages' do
    conversation_with_today_messages = create(:conversation, account: account, inbox: inbox, created_at: 3.days.ago)
    create(:message, account: account, inbox: inbox, conversation: conversation_with_today_messages, content: 'mensagem antiga',
                     created_at: period_start.prev_day.noon)
    create(:message, account: account, inbox: inbox, conversation: conversation_with_today_messages, content: 'mensagem hoje',
                     created_at: period_start.noon)
    create(:message, account: account, inbox: inbox, conversation: conversation_with_today_messages, content: 'resposta hoje',
                     message_type: 'outgoing', created_at: period_start.noon + 5.minutes)

    conversation_without_today_messages = create(:conversation, account: account, inbox: inbox, created_at: period_start.noon)
    create(:message, account: account, inbox: inbox, conversation: conversation_without_today_messages, content: 'fora do periodo',
                     created_at: period_start.prev_day.noon)

    service = instance_double(Captain::Llm::ConversationInsightService, analyze: payload)
    expect(Captain::Llm::ConversationInsightService).to receive(:new)
      .with(hash_including(conversations: [conversation_with_today_messages], period_start: period_start, period_end: period_end))
      .and_return(service)

    described_class.perform_now(account.id, nil, period_start, period_end, inbox.id)

    insight = Captain::ConversationInsight.find_by!(
      account_id: account.id,
      inbox_id: inbox.id,
      period_start: period_start,
      period_end: period_end
    )
    expect(insight.conversations_count).to eq(1)
    expect(insight.messages_count).to eq(2)
    expect(insight).to be_done
  end
end
