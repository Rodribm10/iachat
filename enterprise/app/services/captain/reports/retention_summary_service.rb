# Calcula KPIs agregados de retenção e recorrência para uma account.
# Funciona sobre as colunas desnormalizadas em `contacts` mantidas por
# Captain::Retention::RecalculateContactStatsJob — stats a partir das colunas
# são O(1) por KPI (count + where), sem precisar varrer mensagens.
#
# Janela temporal do período: [period_start, period_end]. Default: mês corrente.
# Cortes de status absolutos (ativo/dormindo/etc) sempre relativos a Time.current,
# independentemente do período — o período afeta apenas as métricas de fluxo
# ("novos no período", "retorno no período").
class Captain::Reports::RetentionSummaryService
  SLEEPING_WINDOW = (30.days)..(90.days)
  AT_RISK_WINDOW = (90.days)..(180.days)
  RETENTION_30D_WINDOW = 30.days
  RETENTION_90D_WINDOW = 90.days

  def initialize(account:, period_start: nil, period_end: nil)
    @account = account
    @period_start = period_start&.to_date || Time.current.beginning_of_month.to_date
    @period_end = period_end&.to_date || Time.current.to_date
  end

  def call
    {
      period: {
        start: @period_start.iso8601,
        end: @period_end.iso8601
      },
      status: status_counts,
      flow: flow_counts,
      pix: pix_counts,
      retention: retention_rates
    }
  end

  private

  def contacts
    @contacts ||= @account.contacts
  end

  # Cortes de status pelo estado atual (Time.current)
  # rubocop:disable Metrics/AbcSize
  def status_counts
    now = Time.current

    active = contacts.where('last_interaction_at >= ?', now - 30.days).count
    recurring = contacts.where(is_recurring: true)
                        .where('last_interaction_at >= ?', now - 90.days).count
    sleeping = contacts.where(last_interaction_at: (now - SLEEPING_WINDOW.max)..(now - SLEEPING_WINDOW.min)).count
    at_risk = contacts.where(last_interaction_at: (now - AT_RISK_WINDOW.max)..(now - AT_RISK_WINDOW.min)).count
    churned = contacts.where('last_interaction_at < ?', now - 180.days).count
    never_interacted = contacts.where(last_interaction_at: nil).count

    {
      active: active,
      recurring: recurring,
      sleeping: sleeping,
      at_risk: at_risk,
      churned: churned,
      never_interacted: never_interacted
    }
  end
  # rubocop:enable Metrics/AbcSize

  # Fluxo dentro do período
  def flow_counts
    period_range = @period_start.beginning_of_day..@period_end.end_of_day

    new_in_period = contacts.where(first_interaction_at: period_range).count
    returned_in_period = contacts
                         .where('first_interaction_at < ?', period_range.begin)
                         .where(last_interaction_at: period_range)
                         .count

    {
      new: new_in_period,
      returned: returned_in_period,
      total_touches: new_in_period + returned_in_period
    }
  end

  # Pix gerado e pago no período (globais, baseado em PixCharge)
  def pix_counts
    period_range = @period_start.beginning_of_day..@period_end.end_of_day

    generated = Captain::PixCharge.where(created_at: period_range).where(unit_id: account_unit_ids).count
    paid = Captain::PixCharge.where(paid_at: period_range).where(unit_id: account_unit_ids).count

    conversion = generated.zero? ? 0.0 : (paid.to_f / generated).round(4)

    {
      generated: generated,
      paid: paid,
      conversion_rate: conversion
    }
  end

  def account_unit_ids
    @account_unit_ids ||= Captain::Unit.where(account_id: @account.id).pluck(:id)
  end

  # Taxa de retorno: dos contatos cuja PRIMEIRA interação foi há {N} dias atrás
  # (ex: [N-step, N]), quantos voltaram a interagir nos últimos {step} dias.
  # Para 30d: cohort da semana entre 30-37d atrás, retorno nos últimos 7d.
  def retention_rates
    {
      last_30d: retention_rate(RETENTION_30D_WINDOW, 7.days),
      last_90d: retention_rate(RETENTION_90D_WINDOW, 14.days)
    }
  end

  def retention_rate(window, step)
    now = Time.current
    cohort_start = now - window - step
    cohort_end = now - window

    cohort = contacts
             .where(first_interaction_at: cohort_start..cohort_end)
    cohort_size = cohort.count
    return 0.0 if cohort_size.zero?

    returned = cohort.where('last_interaction_at > first_interaction_at + interval \'1 day\'')
                     .where('last_interaction_at >= ?', now - step)
                     .count

    (returned.to_f / cohort_size).round(4)
  end
end
