class Api::V1::Accounts::LeadClickStatsController < Api::V1::Accounts::BaseController
  def index
    clicks = account_clicks
    total  = clicks.count
    convs  = clicks.where.not(conversation_id: nil).count

    render json: {
      total_clicks: total,
      total_conversions: convs,
      conversion_rate: total.positive? ? (convs.to_f / total * 100).round(1) : 0,
      by_source: group_by(clicks, :source),
      by_campaign: group_by(clicks, :campanha),
      by_hostname: group_by(clicks, :hostname)
    }
  end

  private

  def account_clicks
    LeadClick.joins(:inbox).where(inboxes: { account_id: current_account.id })
  end

  def group_by(clicks, column)
    clicks
      .group(column)
      .select("#{column}, COUNT(*) AS clicks, COUNT(conversation_id) AS conversions")
      .map do |r|
        {
          label: r.public_send(column).presence || '(sem nome)',
          clicks: r.clicks,
          conversions: r.conversions,
          rate: r.clicks.positive? ? (r.conversions.to_f / r.clicks * 100).round(1) : 0
        }
      end
      .sort_by { |r| -r[:clicks] }
  end
end
