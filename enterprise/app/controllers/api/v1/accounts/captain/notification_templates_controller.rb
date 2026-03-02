class Api::V1::Accounts::Captain::NotificationTemplatesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }
  before_action :set_unit
  before_action :set_template, only: [:update, :destroy]

  def index
    @templates = @unit.notification_templates.ordered
    render json: @templates
  end

  def create
    @template = @unit.notification_templates.new(template_params)
    @template.save!
    render json: @template, status: :created
  end

  def update
    @template.update!(template_params)
    render json: @template
  end

  def destroy
    @template.destroy!
    head :no_content
  end

  private

  def set_unit
    @unit = Current.account.captain_units.find(params[:unit_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Unidade não encontrada' }, status: :not_found
  end

  def set_template
    @template = @unit.notification_templates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Template não encontrado' }, status: :not_found
  end

  def template_params
    params.require(:notification_template).permit(
      :label,
      :content,
      :timing_minutes,
      :timing_direction,
      :active,
      :position
    )
  end
end
