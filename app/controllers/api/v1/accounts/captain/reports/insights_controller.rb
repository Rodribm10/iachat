class Api::V1::Accounts::Captain::Reports::InsightsController < Api::V1::Accounts::BaseController
  # rubocop:disable Metrics/AbcSize
  def index
    unit_id = params[:unit_id].present? ? params[:unit_id].to_i : nil
    inbox_id = params[:inbox_id].present? ? params[:inbox_id].to_i : nil

    scope = Captain::ConversationInsight.where(account_id: Current.account.id)
    scope = scope.where(captain_unit_id: unit_id) if unit_id
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope = scope.where(captain_unit_id: nil, inbox_id: nil) if !unit_id && !inbox_id

    insights = scope.order(period_start: :desc).limit(12)

    render json: insights.map { |i| format_insight(i) }
  end
  # rubocop:enable Metrics/AbcSize

  def show
    insight = Captain::ConversationInsight.find_by!(
      id: params[:id],
      account_id: Current.account.id
    )
    render json: format_insight(insight)
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Insight não encontrado' }, status: :not_found
  end

  # rubocop:disable Metrics/AbcSize
  def generate
    period_start = parse_date(params[:period_start], Time.zone.today.beginning_of_week - 1.week)
    period_end   = parse_date(params[:period_end], Time.zone.today.beginning_of_week - 1.day)
    unit_id      = params[:unit_id].present? ? params[:unit_id].to_i : nil
    inbox_id     = params[:inbox_id].present? ? params[:inbox_id].to_i : nil

    enqueue_insight(unit_id, inbox_id, period_start, period_end)
  end
  # rubocop:enable Metrics/AbcSize

  private

  def enqueue_insight(unit_id, inbox_id, period_start, period_end)
    insight = find_or_init_insight(unit_id, inbox_id, period_start, period_end)
    return render json: { status: 'processing', message: 'Análise já está em andamento' } if insight.processing?

    reset_and_enqueue!(insight, unit_id, inbox_id, period_start, period_end)
  end

  def find_or_init_insight(unit_id, inbox_id, period_start, period_end)
    Captain::ConversationInsight.find_or_initialize_by(
      account_id: Current.account.id,
      captain_unit_id: unit_id,
      inbox_id: inbox_id,
      period_start: period_start,
      period_end: period_end
    )
  end

  def reset_and_enqueue!(insight, unit_id, inbox_id, period_start, period_end)
    insight.status = 'pending'
    insight.payload = nil
    insight.save!
    Captain::Reports::GenerateInsightsJob.perform_later(
      Current.account.id, unit_id, period_start, period_end, inbox_id
    )
    render json: { status: 'queued', insight_id: insight.id }, status: :accepted
  rescue StandardError => e
    Rails.logger.error "Error generating insight: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "Erro ao enfileirar análise: #{e.message}" }, status: :internal_server_error
  end

  def parse_date(param, default)
    param.present? ? Date.parse(param) : default
  rescue ArgumentError
    default
  end

  def format_insight(insight)
    {
      id: insight.id,
      unit_id: insight.captain_unit_id,
      inbox_id: insight.inbox_id,
      period_start: insight.period_start,
      period_end: insight.period_end,
      status: insight.status,
      conversations_count: insight.conversations_count,
      messages_count: insight.messages_count,
      generated_at: insight.generated_at,
      payload: insight.payload
    }
  end
end
