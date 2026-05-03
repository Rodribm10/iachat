# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::Captain::ReservationsController < Api::V1::Accounts::BaseController
  CONFIRMED_STATUSES = %i[scheduled active completed confirmed].freeze
  RESULTS_PER_PAGE = 25
  MAX_RESULTS_PER_PAGE = 100
  SORTABLE_FIELDS = %w[check_in_at created_at updated_at].freeze

  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }
  before_action :set_current_page, only: [:index]
  before_action :set_per_page, only: [:index]
  before_action :set_reservations_scope
  before_action :set_reservation, only: [:show, :pix, :cancel, :mark_as_paid, :regenerate_pix]

  def index
    common_scoped = apply_common_filters(@reservations_scope)
    @status_counts = status_counts_for(common_scoped)
    scoped = apply_status_filter(common_scoped)
    scoped = apply_sort(scoped)
    @reservations_count = scoped.count
    @reservations = scoped.page(@current_page).per(@per_page)
  end

  def revenue
    scoped = apply_common_filters(@reservations_scope.where(status: CONFIRMED_STATUSES))
    render json: Captain::Reservations::RevenueSummaryService.new(scope: scoped).perform
  end

  def show
    @marker = Captain::Reservations::MarkerBuilder.build_for(@reservation)
  end

  def create
    ActiveRecord::Base.transaction do
      @reservation = @reservations_scope.new(create_params)
      @reservation.created_by = current_user
      @reservation.metadata ||= {}

      ensure_contact_inbox!

      if @reservation.save
        @marker = Captain::Reservations::MarkerBuilder.build_for(@reservation)
        render 'api/v1/accounts/captain/reservations/show'
      else
        render json: { error: @reservation.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end
  end

  def pix
    marker = Captain::Reservations::MarkerBuilder.build_for(@reservation)
    render json: {
      reservation_id: @reservation.id,
      pix_copy_paste: marker['pix_copy_paste'],
      reason: marker['pix_reason'],
      status: marker['pix_status']
    }
  end

  def cancel
    reason = params[:reason].to_s.strip
    @reservation.metadata ||= {}
    @reservation.metadata['cancelled_by_user_id'] = current_user.id
    @reservation.metadata['cancelled_at'] = Time.current.iso8601
    @reservation.metadata['cancel_reason'] = reason if reason.present?
    @reservation.update!(status: :cancelled)
    @marker = Captain::Reservations::MarkerBuilder.build_for(@reservation)
    render 'api/v1/accounts/captain/reservations/show'
  end

  def mark_as_paid
    @reservation.metadata ||= {}
    @reservation.metadata['manual_payment_by_user_id'] = current_user.id
    @reservation.metadata['manual_payment_at'] = Time.current.iso8601
    @reservation.metadata['manual_payment_note'] = params[:note].to_s.strip if params[:note].present?
    @reservation.update!(status: :scheduled, payment_status: 'paid')
    @reservation.current_pix_charge&.update!(status: 'paid') if @reservation.current_pix_charge.present?
    @marker = Captain::Reservations::MarkerBuilder.build_for(@reservation)
    render 'api/v1/accounts/captain/reservations/show'
  end

  def regenerate_pix
    raise 'Reservation not configured for PIX' if @reservation.unit.blank?

    @reservation.current_pix_charge&.update!(status: 'expired')
    Captain::Inter::CobService.new(@reservation).call
    @reservation.update!(status: :pending_payment)
    @reservation.reload
    @marker = Captain::Reservations::MarkerBuilder.build_for(@reservation)
    render 'api/v1/accounts/captain/reservations/show'
  rescue StandardError => e
    render json: { error: "Falha ao regerar PIX: #{e.message}" }, status: :unprocessable_entity
  end

  private

  def set_reservations_scope
    scope = Current.account.captain_reservations
                   .includes(:contact, :unit, :conversation, :current_pix_charge)
    @reservations_scope = filter_by_user_inbox_access(scope)
  end

  # Agentes só enxergam reservas em caixas de entrada que eles podem acessar.
  def filter_by_user_inbox_access(scope)
    return scope if Current.user.administrator?

    accessible_inbox_ids = Current.user.assigned_inboxes.pluck(:id)
    return scope.none if accessible_inbox_ids.empty?

    scope.where(inbox_id: accessible_inbox_ids)
  end

  def set_reservation
    @reservation = @reservations_scope.find(permitted_params[:id])
  end

  def set_current_page
    @current_page = permitted_params[:page].presence || 1
  end

  def set_per_page
    requested = permitted_params[:per_page].presence || RESULTS_PER_PAGE
    @per_page = [requested.to_i, MAX_RESULTS_PER_PAGE].min
    @per_page = RESULTS_PER_PAGE if @per_page <= 0
  end

  def apply_filters(scope)
    apply_status_filter(apply_common_filters(scope))
  end

  def apply_common_filters(scope)
    scoped = scope
    scoped = apply_date_filter(scoped)
    scoped = scoped.where(captain_unit_id: permitted_params[:unit_id]) if permitted_params[:unit_id].present?
    scoped = apply_suite_filter(scoped)
    apply_search(scoped)
  end

  def apply_status_filter(scope)
    status = permitted_params[:status].to_s
    return scope if status.blank? || status == 'all'

    return scope.where(status: CONFIRMED_STATUSES) if status == 'confirmed'

    return scope unless Captain::Reservation.statuses.key?(status)

    scope.where(status: status)
  end

  def apply_suite_filter(scope)
    suite = permitted_params[:suite].to_s.strip
    return scope if suite.blank?

    scope.where('LOWER(captain_reservations.suite_identifier) LIKE ?', "%#{suite.downcase}%")
  end

  def apply_date_filter(scope)
    from = parse_date(permitted_params[:date_from])
    to = parse_date(permitted_params[:date_to])
    return scope if from.blank? && to.blank?

    if from.present? && to.present?
      scope.where(check_in_at: from.beginning_of_day..to.end_of_day)
    elsif from.present?
      scope.where('check_in_at >= ?', from.beginning_of_day)
    else
      scope.where('check_in_at <= ?', to.end_of_day)
    end
  end

  def apply_search(scope)
    query = permitted_params[:q].to_s.strip
    return scope if query.blank?

    like = "%#{query.downcase}%"

    scope.joins(:contact).where(
      "LOWER(contacts.name) LIKE :q OR LOWER(contacts.phone_number) LIKE :q OR LOWER(COALESCE(contacts.custom_attributes ->> 'cpf', '')) LIKE :q",
      q: like
    )
  end

  def status_counts_for(scope)
    counts_by_status = scope.group(:status).count.transform_keys do |key|
      Captain::Reservation.statuses.key(key) || key.to_s
    end
    confirmed_count = CONFIRMED_STATUSES.sum { |status| counts_by_status[status.to_s].to_i }

    {
      all: counts_by_status.values.sum,
      draft: counts_by_status['draft'].to_i,
      pending_payment: counts_by_status['pending_payment'].to_i,
      confirmed: confirmed_count,
      cancelled: counts_by_status['cancelled'].to_i
    }
  end

  def apply_sort(scope)
    return default_order(scope) if permitted_params[:sort].blank?

    sort_field = permitted_params[:sort].to_s
    return default_order(scope) unless SORTABLE_FIELDS.include?(sort_field)

    direction = permitted_params[:direction].to_s.downcase == 'asc' ? 'ASC' : 'DESC'
    scope.order(Arel.sql("#{sort_field} #{direction}"))
  end

  def default_order(scope)
    scope.order(
      Arel.sql(
        'CASE captain_reservations.status ' \
        "WHEN #{Captain::Reservation.statuses[:scheduled]} THEN 0 " \
        "WHEN #{Captain::Reservation.statuses[:active]} THEN 0 " \
        "WHEN #{Captain::Reservation.statuses[:completed]} THEN 0 " \
        "WHEN #{Captain::Reservation.statuses[:confirmed]} THEN 0 " \
        "WHEN #{Captain::Reservation.statuses[:pending_payment]} THEN 1 " \
        "WHEN #{Captain::Reservation.statuses[:draft]} THEN 2 " \
        "WHEN #{Captain::Reservation.statuses[:cancelled]} THEN 3 " \
        'ELSE 4 END ASC, captain_reservations.check_in_at ASC'
      )
    )
  end

  def parse_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end

  def permitted_params
    params.permit(
      :id, :account_id, :status, :date_from, :date_to, :unit_id, :suite, :q,
      :page, :per_page, :sort, :direction
    )
  end

  def create_params
    params.require(:reservation).permit(
      :contact_id, :inbox_id, :captain_unit_id, :suite_identifier,
      :check_in_at, :check_out_at, :total_amount
    )
  end

  def ensure_contact_inbox!
    return if @reservation.contact_inbox_id.present? || @reservation.contact_id.blank? || @reservation.inbox_id.blank?

    contact_inbox = ContactInbox.find_or_create_by!(
      contact_id: @reservation.contact_id,
      inbox_id: @reservation.inbox_id
    ) do |ci|
      ci.source_id = SecureRandom.uuid
    end

    @reservation.contact_inbox_id = contact_inbox.id
  end
end
# rubocop:enable Metrics/ClassLength
