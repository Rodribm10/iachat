class Api::V1::Accounts::Captain::LifecycleRulesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Lifecycle::Rule) }
  before_action :set_rule, only: [:show, :update, :destroy]

  def index
    @rules = Current.account.captain_lifecycle_rules.order(priority: :asc, id: :desc)
  end

  def show; end

  def create
    @rule = Current.account.captain_lifecycle_rules.create!(
      rule_params.merge(created_by_user: Current.user)
    )
    render 'api/v1/accounts/captain/lifecycle_rules/show'
  end

  def update
    @rule.update!(rule_params)
    render 'api/v1/accounts/captain/lifecycle_rules/show'
  end

  def destroy
    @rule.destroy!
    head :no_content
  end

  private

  def set_rule
    @rule = Current.account.captain_lifecycle_rules.find(params[:id])
  end

  def rule_params
    params.require(:rule).permit(
      :name, :description, :enabled, :event, :offset_minutes,
      :message_type, :message_body, :priority,
      filters: {},
      message_payload: {}
    )
  end
end
