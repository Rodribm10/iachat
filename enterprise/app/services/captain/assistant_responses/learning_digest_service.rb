# Resumo semanal do ciclo de aprendizado, por atendente.
#
# É o que substitui a fila de aprovação: em vez de alguém precisar aprovar
# cada FAQ para o loop andar, o loop anda sozinho e o humano recebe o retrato
# do que foi aprendido — e só age no que o juiz reprovou.
class Captain::AssistantResponses::LearningDigestService
  def initialize(account:, period_start:, period_end:)
    @account = account
    @period_start = period_start.to_date
    @period_end = period_end.to_date
  end

  def call
    rows = assistants.map { |assistant| build_row(assistant) }.reject { |row| row[:total].zero? }

    {
      account_id: account.id,
      account_name: account.name,
      period_start: period_start,
      period_end: period_end,
      by_assistant: rows,
      totals: build_totals(rows)
    }
  end

  private

  attr_reader :account, :period_start, :period_end

  def period
    @period ||= period_start.beginning_of_day..period_end.end_of_day
  end

  def assistants
    account.captain_assistants.order(:name)
  end

  def learned_scope(assistant)
    assistant.responses.where(source: 'human_validated')
  end

  def build_row(assistant)
    scope = learned_scope(assistant)

    aprendidas = scope.where(created_at: period).count
    em_quarentena = scope.trial.count
    promovidas = scope.where(promoted_at: period).count
    aguardando_humano = scope.pending.count
    aposentadas = scope.where(retired_at: period).count

    {
      assistant_id: assistant.id,
      assistant_name: assistant.name,
      aprendidas: aprendidas,
      em_quarentena: em_quarentena,
      promovidas: promovidas,
      aposentadas: aposentadas,
      aguardando_humano: aguardando_humano,
      total: aprendidas + em_quarentena + promovidas + aposentadas + aguardando_humano
    }
  end

  def build_totals(rows)
    %i[aprendidas em_quarentena promovidas aposentadas aguardando_humano].index_with do |key|
      rows.sum { |row| row[key] }
    end
  end
end
