class Captain::Reports::WeeklyInsightsJob < ApplicationJob
  queue_as :scheduled_jobs

  # Roda todo domingo de madrugada via Sidekiq-Cron.
  # Agenda geração de insights para todas as unidades de todas as contas.
  def perform
    period_end = Date.yesterday
    period_start = period_end - 6.days

    Account.find_each do |account|
      # Gera um insight global (sem unit) para a conta toda
      Captain::Reports::GenerateInsightsJob.perform_later(
        account.id, nil, period_start, period_end
      )

      # Gera um insight por unidade
      account.captain_units.find_each do |unit|
        Captain::Reports::GenerateInsightsJob.perform_later(
          account.id, unit.id, period_start, period_end
        )
      end
    end
  end
end
