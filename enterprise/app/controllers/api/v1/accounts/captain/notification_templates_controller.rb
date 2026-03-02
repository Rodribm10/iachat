class Api::V1::Accounts::Captain::NotificationTemplatesController < Api::V1::Accounts::BaseController
  before_action :set_inbox
  before_action :set_template, only: [:update, :destroy]

  def index
    templates = @inbox.captain_notification_templates.ordered
    render json: templates
  end

  def create
    template = @inbox.captain_notification_templates.new(template_params)
    if template.save
      render json: template, status: :created
    else
      render json: { error: template.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @template.update(template_params)
      render json: @template
    else
      render json: { error: @template.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy!
    head :no_content
  end

  private

  def set_inbox
    @inbox = current_account.inboxes.find(params[:inbox_id])
  end

  def set_template
    @template = @inbox.captain_notification_templates.find(params[:id])
  end

  def template_params
    params.require(:notification_template).permit(:label, :content, :timing_minutes, :timing_direction, :active, :position)
  end
end
