class V2::Reports::BotMetricsBuilder
  include DateRangeHelper
  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  def metrics
    {
      conversation_count: bot_conversations.count,
      message_count: bot_messages.count,
      resolution_rate: bot_resolution_rate.to_i,
      handoff_rate: total_handoff_rate.to_i,
      bot_resolutions_count: bot_resolutions_count,
      auto_handoffs_count: auto_handoffs_count,
      manual_takeovers_count: manual_takeovers_count
    }
  end

  private

  def filter_inbox_id
    @filter_inbox_id ||= params[:inbox_id].presence&.to_i
  end

  def bot_activated_inbox_ids
    @bot_activated_inbox_ids ||= begin
      ids = account.inboxes.filter(&:active_bot?).map(&:id)
      filter_inbox_id ? ids & [filter_inbox_id] : ids
    end
  end

  def bot_conversations
    @bot_conversations ||= account.conversations.where(inbox_id: bot_activated_inbox_ids).where(created_at: range)
  end

  def bot_messages
    @bot_messages ||= account.messages.outgoing.where(conversation_id: bot_conversations.ids).where(created_at: range)
  end

  def base_reporting_events
    scope = account.reporting_events.where(account_id: account.id, created_at: range)
    scope = scope.where(inbox_id: filter_inbox_id) if filter_inbox_id
    scope
  end

  def bot_resolutions_count
    # Handoff manda: conversa que teve handoff no mesmo periodo nao conta como
    # resolvida pelo bot (regra que veio do upstream no 4.14).
    @bot_resolutions_count ||= base_reporting_events.joins(:conversation)
                                                    .select(:conversation_id)
                                                    .where(name: :conversation_bot_resolved)
                                                    .where.not(conversation_id: bot_handoff_conversation_ids_subquery)
                                                    .distinct.count
  end

  def bot_handoff_conversation_ids_subquery
    base_reporting_events.where(name: :conversation_bot_handoff)
                         .where.not(conversation_id: nil)
                         .select(:conversation_id)
  end

  # Auto handoff = Jasmine called bot_handoff! explicitly (loop, timeout, max_turns, intent)
  def auto_handoffs_count
    @auto_handoffs_count ||= base_reporting_events.joins(:conversation)
                                                  .select(:conversation_id)
                                                  .where(name: :conversation_bot_handoff)
                                                  .distinct.count
  end

  # Manual takeover = a human replied (via Chatwoot UI or WhatsApp echo) WITHOUT a bot_handoff
  # event being emitted for the same conversation. The bot itself uses sender_type 'Captain::Assistant',
  # so it's never counted here.
  def manual_takeovers_count
    @manual_takeovers_count ||= begin
      conv_ids_with_human_reply = bot_conversations
                                  .joins(:messages)
                                  .where(messages: { message_type: :outgoing })
                                  .where('messages.sender_type = ? OR messages.sender_type IS NULL', 'User')
                                  .distinct
                                  .pluck(:id)

      conv_ids_with_auto_handoff = ReportingEvent.unscope(:order)
                                                 .where(name: 'conversation_bot_handoff',
                                                        conversation_id: conv_ids_with_human_reply)
                                                 .distinct
                                                 .pluck(:conversation_id)

      (conv_ids_with_human_reply - conv_ids_with_auto_handoff).count
    end
  end

  def bot_resolution_rate
    return 0 if bot_conversations.count.zero?

    bot_resolutions_count.to_f / bot_conversations.count * 100
  end

  # Total handoff = auto + manual (the gear that closes the math now)
  def total_handoff_rate
    return 0 if bot_conversations.count.zero?

    (auto_handoffs_count + manual_takeovers_count).to_f / bot_conversations.count * 100
  end
end
