class Api::V1::Accounts::Captain::UnitsController < Api::V1::Accounts::BaseController
  before_action :ensure_captain_enabled
  before_action :set_unit, only: [:show, :update, :destroy]

  def index
    @units = Current.account.captain_units
    render json: @units.map { |u| format_unit(u) }
  end

  def show
    render json: format_unit(@unit)
  end

  def create
    @unit = Current.account.captain_units.build(unit_params)
    @unit.captain_brand_id ||= Captain::Brand.where(account_id: Current.account.id).first&.id
    ActiveRecord::Base.transaction do
      @unit.save!
      sync_inbox_link!(@unit)
    end
    render json: format_unit(@unit), status: :created
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @unit.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    ActiveRecord::Base.transaction do
      @unit.update!(unit_params)
      sync_inbox_link!(@unit)
    end
    render json: format_unit(@unit)
  rescue ActiveRecord::RecordInvalid
    render json: { errors: @unit.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @unit.destroy!
    head :no_content
  end

  private

  def ensure_captain_enabled
    # Dependendo da regra de negócio, pode-se verificar as features da conta aqui original
  end

  def set_unit
    @unit = Current.account.captain_units.find(params[:id])
  end

  def unit_params
    params.require(:captain_unit).permit(
      :name,
      :inter_client_id,
      :inter_client_secret,
      :inter_pix_key,
      :inter_account_number,
      :inbox_id,
      :inter_cert_content,
      :inter_key_content,
      :proactive_pix_polling_enabled
    )
  end

  def format_unit(unit)
    {
      id: unit.id,
      name: unit.name,
      inter_client_id: unit.inter_client_id,
      inter_pix_key: unit.inter_pix_key,
      inter_account_number: unit.inter_account_number,
      inbox_id: unit.inbox_id,
      inbox_name: unit.inbox_id.present? ? Inbox.find_by(id: unit.inbox_id)&.name : nil,
      has_cert: unit.inter_cert_content.present? || unit.resolved_inter_cert_path.present?,
      has_key: unit.inter_key_content.present? || unit.resolved_inter_key_path.present?,
      has_client_secret: unit.inter_client_secret.present?,
      proactive_pix_polling_enabled: unit.proactive_pix_polling_enabled
      # Obviamente não enviando secrets ou contents aqui!
    }
  end

  def sync_inbox_link!(unit)
    if unit.inbox_id.present?
      Current.account.captain_units
             .where(inbox_id: unit.inbox_id)
             .where.not(id: unit.id)
             .find_each { |existing_unit| existing_unit.update!(inbox_id: nil) }
    end

    return unless defined?(CaptainInbox)

    CaptainInbox.where(captain_unit_id: unit.id).find_each do |existing_link|
      existing_link.update!(captain_unit_id: nil)
    end

    return if unit.inbox_id.blank?

    inbox_link = CaptainInbox.find_by(inbox_id: unit.inbox_id)
    inbox_link&.update!(captain_unit_id: unit.id)
  end
end
