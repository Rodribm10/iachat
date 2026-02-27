class Captain::Reports::GenerateInsightsJob < ApplicationJob
  queue_as :default

  # Gera insights de IA para uma unidade ou inbox específica em um período.
  # Pode ser disparado on-demand (botão na UI) ou pelo WeeklyInsightsJob.
  def perform(account_id, unit_id, period_start, period_end, inbox_id = nil)
    account = Account.find_by(id: account_id)
    return unless account

    unit = account.captain_units.find_by(id: unit_id) if unit_id
    inbox = account.inboxes.find_by(id: inbox_id) if inbox_id

    insight = find_or_create_insight(account_id, unit_id, inbox_id, period_start, period_end)
    return if insight.processing? || insight.done?

    insight.mark_processing!
    run_analysis(account, unit, inbox, insight, period_start, period_end)
  rescue StandardError => e
    Rails.logger.error "[Captain::Reports::GenerateInsightsJob] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    insight&.mark_failed!
  end

  private

  def find_or_create_insight(account_id, unit_id, inbox_id, period_start, period_end)
    insight = Captain::ConversationInsight.find_or_initialize_by(
      account_id: account_id,
      captain_unit_id: unit_id,
      inbox_id: inbox_id,
      period_start: period_start,
      period_end: period_end
    )
    insight.save! if insight.new_record?
    insight
  end

  def run_analysis(account, unit, inbox, insight, period_start, period_end)
    conversations = fetch_conversations(account, unit, inbox, period_start, period_end)
    insight.update!(conversations_count: conversations.count)

    payload = Captain::Llm::ConversationInsightService.new(
      account: account,
      unit: unit,
      inbox: inbox,
      conversations: conversations
    ).analyze

    insight.update!(messages_count: conversations.sum { |conv| conv.messages.count })
    insight.mark_done!(payload)
  end

  def fetch_conversations(account, unit, inbox, period_start, period_end)
    scope = account.conversations
                   .where(created_at: period_start.beginning_of_day..period_end.end_of_day)
                   .includes(:messages)

    if inbox
      scope = scope.where(inbox_id: inbox.id)
    elsif unit
      inbox_ids = unit.inboxes.pluck(:id)
      scope = scope.where(inbox_id: inbox_ids) if inbox_ids.any?
    end

    scope.to_a
  end
end
