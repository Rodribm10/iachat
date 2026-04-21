class Captain::Reports::WeeklyInsightsJob < ApplicationJob
  queue_as :scheduled_jobs

  # Roda todo domingo de madrugada via Sidekiq-Cron.
  # Agenda geração de insights:
  #   - 1 global por conta (account toda)
  #   - 1 por Captain::Unit (agrupamento lógico de marca, se houver)
  #   - 1 por Inbox (cada canal é uma "unidade" do ponto de vista operacional)
  def perform
    period_end = Date.yesterday
    period_start = period_end - 6.days

    Account.find_each do |account|
      enqueue_global(account, period_start, period_end)
      enqueue_per_captain_unit(account, period_start, period_end)
      enqueue_per_inbox(account, period_start, period_end)
    end
  end

  private

  def enqueue_global(account, period_start, period_end)
    Captain::Reports::GenerateInsightsJob.perform_later(
      account.id, nil, period_start, period_end
    )
  end

  def enqueue_per_captain_unit(account, period_start, period_end)
    account.captain_units.find_each do |unit|
      Captain::Reports::GenerateInsightsJob.perform_later(
        account.id, unit.id, period_start, period_end
      )
    end
  end

  def enqueue_per_inbox(account, period_start, period_end)
    account.inboxes.find_each do |inbox|
      Captain::Reports::GenerateInsightsJob.perform_later(
        account.id, nil, period_start, period_end, inbox.id
      )
    end
  end
end
