class Api::V1::Accounts::LeadClickStatsController < Api::V1::Accounts::BaseController
  def show
    clicks = account_clicks
    render json: stats_payload(clicks)
  end

  private

  def account_clicks
    scope = LeadClick.joins(:inbox).where(inboxes: { account_id: current_account.id })
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    apply_period_filter(scope)
  end

  def apply_period_filter(scope)
    return scope unless params[:period_start].present? && params[:period_end].present?

    start_at = Time.zone.parse(params[:period_start].to_s)&.beginning_of_day
    end_at = Time.zone.parse(params[:period_end].to_s)&.end_of_day
    return scope unless start_at && end_at

    scope.where(created_at: start_at..end_at)
  end

  def stats_payload(clicks)
    total_clicks = clicks.count
    total_conversions = clicks.where.not(conversation_id: nil).count
    total_non_converted = total_clicks - total_conversions

    {
      total_clicks: total_clicks,
      total_conversions: total_conversions,
      total_non_converted: total_non_converted,
      drop_off_rate: percentage(total_non_converted, total_clicks),
      conversion_rate: percentage(total_conversions, total_clicks),
      unique_click_ids: clicks.where.not(click_id: [nil, '']).distinct.count(:click_id),
      unique_converted_contacts: clicks.where.not(contact_id: nil).distinct.count(:contact_id),
      daily: daily_breakdown(clicks),
      by_source: group_by(clicks, :source),
      by_campaign: group_by(clicks, :campanha),
      by_hostname: group_by(clicks, :hostname)
    }
  end

  def percentage(part, total)
    return 0 unless total.positive?

    (part.to_f / total * 100).round(1)
  end

  def group_by(clicks, column)
    rows = clicks
           .group(column)
           .select("#{column}, COUNT(*) AS clicks, COUNT(conversation_id) AS conversions")

    grouped_rows = rows.map do |row|
      {
        label: row.public_send(column).presence || '(sem nome)',
        clicks: row.clicks,
        conversions: row.conversions,
        rate: row.clicks.positive? ? (row.conversions.to_f / row.clicks * 100).round(1) : 0
      }
    end

    grouped_rows.sort_by { |row| -row[:clicks] }
  end

  def daily_breakdown(clicks)
    rows = clicks
           .group('DATE(lead_clicks.created_at)')
           .select('DATE(lead_clicks.created_at) AS day, COUNT(*) AS clicks, COUNT(lead_clicks.conversation_id) AS conversions')
           .order('day ASC')

    rows.map do |row|
      {
        day: row.day.to_s,
        clicks: row.clicks.to_i,
        conversions: row.conversions.to_i,
        non_converted: row.clicks.to_i - row.conversions.to_i
      }
    end
  end
end
