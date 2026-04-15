class Api::V1::Accounts::Captain::LifecycleDeliveriesController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25
  MAX_RESULTS_PER_PAGE = 100

  before_action :current_account
  before_action -> { check_authorization(Captain::Lifecycle::Delivery) }
  before_action :set_page, only: [:index]
  before_action :set_delivery, only: [:show]

  def index
    scope = base_scope
    scope = apply_filters(scope)
    @total_count = scope.count
    @deliveries = scope.page(@page).per(@per_page)
  end

  def show; end

  private

  def set_page
    @page = (params[:page] || 1).to_i
    @per_page = [(params[:per_page] || RESULTS_PER_PAGE).to_i, MAX_RESULTS_PER_PAGE].min
  end

  def set_delivery
    @delivery = Current.account.captain_lifecycle_deliveries.find(params[:id])
  end

  def base_scope
    Current.account.captain_lifecycle_deliveries
           .includes(:lifecycle_rule, captain_reservation: :contact)
           .order(created_at: :desc)
  end

  # rubocop:disable Metrics/AbcSize
  def apply_filters(scope)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(lifecycle_rule_id: params[:rule_id]) if params[:rule_id].present?
    scope = scope.where(captain_reservation_id: params[:reservation_id]) if params[:reservation_id].present?
    scope = scope.where('fire_at >= ?', params[:from]) if params[:from].present?
    scope = scope.where('fire_at <= ?', params[:to]) if params[:to].present?
    scope
  end
  # rubocop:enable Metrics/AbcSize
end
