class Api::V1::Accounts::LandingHostsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox, only: [:index, :create]
  before_action :fetch_landing_host, only: [:update, :destroy]

  def index
    @landing_hosts = LandingHost.where(inbox_id: @inbox.id)
    render json: @landing_hosts
  end

  def create
    @landing_host = LandingHost.new(landing_host_params.merge(inbox_id: @inbox.id, active: true))

    if @landing_host.save
      render json: @landing_host, status: :created
    else
      render json: { error: @landing_host.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @landing_host.update(landing_host_params)
      render json: @landing_host
    else
      render json: { error: @landing_host.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @landing_host.destroy!
    head :no_content
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Inbox not found' }, status: :not_found
  end

  def fetch_landing_host
    # Garantimos que a pessoa só possa acessar/apagar LandingHosts de Inboxes que pertencem a ela
    valid_inbox_ids = Current.account.inboxes.pluck(:id)
    @landing_host = LandingHost.where(inbox_id: valid_inbox_ids).find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Landing Host not found' }, status: :not_found
  end

  def landing_host_params
    params.require(:landing_host).permit(
      :hostname, :unit_code, :active, :auto_label,
      :page_title, :page_subtitle, :button_text, :logo_url,
      :suite_image_url, :theme_color, :whatsapp_number,
      :initial_message, :default_source, :default_campanha
    )
  end
end
