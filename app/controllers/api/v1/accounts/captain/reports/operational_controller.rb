class Api::V1::Accounts::Captain::Reports::OperationalController < Api::V1::Accounts::BaseController
  def show
    period_start = parse_date(params[:period_start], Time.zone.today.beginning_of_month)
    period_end = parse_date(params[:period_end], Time.zone.today)
    unit = params[:unit_id].present? ? Current.account.captain_units.find_by(id: params[:unit_id]) : nil

    render json: build_operational_report(unit, period_start, period_end)
  end

  private

  def parse_date(param, default)
    param.present? ? Date.parse(param) : default
  rescue ArgumentError
    default
  end

  def build_operational_report(unit, period_start, period_end)
    conversations = scoped_conversations(unit, period_start, period_end)

    {
      period: { start: period_start, end: period_end },
      unit_id: unit&.id,
      unit_name: unit&.name,
      conversations: conversation_metrics(conversations),
      reservations: reservation_metrics(unit, period_start, period_end),
      hourly_distribution: hourly_distribution(conversations),
      daily_distribution: daily_distribution(conversations, period_start, period_end)
    }
  end

  def conversation_metrics(conversations)
    resolved = conversations.where(status: 'resolved')
    avg_minutes = avg_resolution_minutes(resolved)

    {
      total: conversations.count,
      resolved: resolved.count,
      open: conversations.where(status: 'open').count,
      resolution_rate: safe_rate(resolved.count, conversations.count),
      avg_resolution_minutes: avg_minutes
    }
  end

  def reservation_metrics(unit, period_start, period_end)
    reservations = scoped_reservations(unit, period_start, period_end)
    paid = reservations.where(status: 'paid')
    expired = reservations.where(status: 'expired')

    {
      total: reservations.count,
      paid: paid.count,
      expired: expired.count,
      pending: reservations.where(status: %w[pending waiting]).count,
      conversion_rate: safe_rate(paid.count, reservations.count),
      total_paid_cents: paid.sum(:amount_cents)
    }
  rescue StandardError
    { total: 0, paid: 0, expired: 0, pending: 0, conversion_rate: 0, total_paid_cents: 0 }
  end

  def hourly_distribution(conversations)
    (0..23).map do |hour|
      count = conversations.where('EXTRACT(HOUR FROM created_at) = ?', hour).count
      { hour: hour, count: count }
    end
  end

  def daily_distribution(conversations, period_start, period_end)
    (period_start..period_end).map do |date|
      count = conversations.where(created_at: date.all_day).count
      { date: date.to_s, count: count }
    end
  end

  def scoped_conversations(unit, period_start, period_end)
    scope = Current.account.conversations.where(created_at: period_start.beginning_of_day..period_end.end_of_day)
    if unit
      inbox_ids = unit.inboxes.pluck(:id)
      scope = scope.where(inbox_id: inbox_ids) if inbox_ids.any?
    end
    scope
  end

  def scoped_reservations(unit, period_start, period_end)
    scope = Current.account.captain_reservations.where(created_at: period_start.beginning_of_day..period_end.end_of_day)
    scope = scope.where(captain_unit_id: unit.id) if unit
    scope
  end

  def avg_resolution_minutes(conversations)
    return 0 if conversations.none?

    total = conversations.sum do |c|
      ((c.updated_at - c.created_at) / 60).round
    end
    (total / conversations.count).round
  end

  def safe_rate(numerator, denominator)
    return 0 if denominator.zero?

    ((numerator.to_f / denominator) * 100).round(1)
  end
end
