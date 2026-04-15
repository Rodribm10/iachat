# frozen_string_literal: true

class Api::V1::Accounts::Captain::LifecycleConfigsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :set_config
  before_action -> { check_authorization(@config) }

  def show; end

  def update
    @config.update!(config_params)
    render 'api/v1/accounts/captain/lifecycle_configs/show'
  end

  private

  def set_config
    @config = Captain::Lifecycle::Config.for_account(Current.account)
  end

  def config_params
    params.require(:config).permit(
      :quiet_hours_enabled, :quiet_hours_from, :quiet_hours_to,
      :min_interval_minutes, :pause_on_customer_reply,
      :pause_on_customer_reply_within_minutes, :opt_out_label_id
    )
  end
end
