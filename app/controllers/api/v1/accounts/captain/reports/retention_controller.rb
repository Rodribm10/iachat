# frozen_string_literal: true

# Endpoints de retenção e recorrência pra Relatórios > Retenção.
# GET /api/v1/accounts/:account_id/captain/reports/retention         → summary (KPIs)
# GET /api/v1/accounts/:account_id/captain/reports/retention/cohort  → matriz cohort
class Api::V1::Accounts::Captain::Reports::RetentionController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  def show
    summary = Captain::Reports::RetentionSummaryService.new(
      account: current_account,
      period_start: params[:start_date],
      period_end: params[:end_date]
    ).call

    render json: summary
  end

  def cohort
    months = params[:history_months].presence&.to_i
    data = Captain::Reports::RetentionCohortService.new(
      account: current_account,
      history_months: months || Captain::Reports::RetentionCohortService::DEFAULT_HISTORY_MONTHS
    ).call

    render json: data
  end
end
