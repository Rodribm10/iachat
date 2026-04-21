# frozen_string_literal: true

class Api::V1::Accounts::Captain::Reports::FunnelController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  def show
    days = params[:period_days].to_i
    report = Captain::Reports::ConversionFunnelService.new(
      account: current_account,
      period_days: days
    ).call
    render json: report
  end
end
