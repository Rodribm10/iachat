class Api::V1::Accounts::Captain::UnitsController < Api::V1::Accounts::BaseController
  before_action :ensure_captain_enabled
  before_action :set_unit, only: [:show, :update, :destroy, :update_concierge]

  def index
    @units = Current.account.captain_units.includes(:inboxes)
    @units = filter_units_by_user_access(@units)
    render json: @units.map { |u| format_unit(u) }
  end

  def show
    render json: format_unit(@unit)
  end

  def create
    @unit = Current.account.captain_units.build(unit_params)
    @unit.captain_brand_id ||= default_brand.id
    ActiveRecord::Base.transaction do
      @unit.save!
      sync_inboxes!(@unit, inbox_ids_param)
    end
    render json: format_unit(@unit), status: :created
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @unit.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    ActiveRecord::Base.transaction do
      @unit.update!(unit_params)
      sync_inboxes!(@unit, inbox_ids_param) if params[:captain_unit].key?(:inbox_ids)
    end
    render json: format_unit(@unit)
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @unit.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @unit.destroy!
    head :no_content
  end

  def update_concierge
    return render json: { error: 'Unauthorized' }, status: :unauthorized unless Current.user.administrator?

    @unit.update!(concierge_params)
    render json: format_unit(@unit)
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @unit.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def ensure_captain_enabled
    # Dependendo da regra de negócio, pode-se verificar as features da conta aqui original
  end

  # Administrador vê todas as unidades; agente só vê unidades vinculadas a
  # alguma caixa de entrada a qual ele tem acesso.
  def filter_units_by_user_access(scope)
    return scope if Current.user.administrator?

    accessible_inbox_ids = Current.user.assigned_inboxes.pluck(:id)
    return scope.none if accessible_inbox_ids.empty?

    scope.joins(:inboxes).where(inboxes: { id: accessible_inbox_ids }).distinct
  end

  def default_brand
    @default_brand ||= Captain::Brand.where(account_id: Current.account.id).first ||
                       Captain::Brand.create!(
                         account_id: Current.account.id,
                         name: 'Marca padrão'
                       )
  end

  def set_unit
    @unit = Current.account.captain_units.includes(:inboxes).find(params[:id])
  end

  def unit_params
    params.require(:captain_unit).permit(
      :name,
      :inter_client_id,
      :inter_client_secret,
      :inter_pix_key,
      :inter_account_number,
      :inter_cert_content,
      :inter_key_content,
      :proactive_pix_polling_enabled
    )
  end

  def concierge_params
    params.require(:captain_unit).permit(
      :concierge_inbox_id,
      concierge_config: [:persona_name, :knowledge, { variables: {} }]
    )
  end

  def inbox_ids_param
    return [] unless params[:captain_unit].key?(:inbox_ids)

    Array(params[:captain_unit][:inbox_ids]).map(&:to_i).select(&:positive?)
  end

  # Sincroniza a lista de inboxes de uma unit: adiciona novas, remove ausentes.
  # Garante que apenas inboxes da mesma conta sejam aceitas.
  def sync_inboxes!(unit, ids)
    valid_ids = Current.account.inboxes.where(id: ids).pluck(:id)

    # Remove vínculos não presentes na nova lista
    unit.unit_inboxes.where.not(inbox_id: valid_ids).destroy_all

    # Adiciona novos vínculos (ignora duplicatas via uniqueness)
    existing_ids = unit.unit_inboxes.pluck(:inbox_id)
    (valid_ids - existing_ids).each do |inbox_id|
      unit.unit_inboxes.create!(inbox_id: inbox_id)
    end
  end

  def format_unit(unit) # rubocop:disable Metrics/AbcSize
    inboxes = unit.inboxes.to_a
    {
      id: unit.id,
      name: unit.name,
      inter_client_id: unit.inter_client_id,
      inter_pix_key: unit.inter_pix_key,
      inter_account_number: unit.inter_account_number,
      inbox_ids: inboxes.map(&:id),
      inbox_names: inboxes.map(&:name),
      # Mantém inbox_id e inbox_name como atalho para compatibilidade com código legado
      inbox_id: inboxes.first&.id,
      inbox_name: inboxes.first&.name,
      has_cert: unit.inter_cert_content.present? || unit.resolved_inter_cert_path.present?,
      has_key: unit.inter_key_content.present? || unit.resolved_inter_key_path.present?,
      has_client_secret: unit.inter_client_secret.present?,
      proactive_pix_polling_enabled: unit.proactive_pix_polling_enabled
    }.merge(format_concierge(unit))
  end

  def format_concierge(unit)
    {
      concierge_inbox_id: unit.concierge_inbox_id,
      concierge_config: unit.concierge_config || {}
    }
  end
end
