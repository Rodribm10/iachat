class Api::V1::Accounts::Inboxes::GowaController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :ensure_gowa_provider

  def show
    render json: client.device_status(device_id)
  rescue Gowa::Client::Error => e
    render_provider_error(e)
  end

  def qr
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
    login_response = client.start_login(device_id)
    qr_link = login_response.dig('results', 'qr_link')
    return render json: login_response if qr_link.blank?

    qr_image = client.download_media(qr_link)
    render json: {
      qrcode: "data:#{qr_image[:content_type].presence || 'image/png'};base64,#{Base64.strict_encode64(qr_image[:body])}",
      expires_in: login_response.dig('results', 'qr_duration'),
      generated_at: Time.current.iso8601
    }
  rescue Gowa::Client::Error => e
    render_provider_error(e)
  end

  def disconnect
    render json: client.logout(device_id)
  rescue Gowa::Client::Error => e
    render_provider_error(e)
  end

  def update_webhook
    client.update_webhook(device_id, expected_webhook_url, webhook_secret)
    render json: { success: true, webhook_url: expected_webhook_url }
  rescue Gowa::Client::Error => e
    render_provider_error(e)
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def ensure_gowa_provider
    return if @inbox.channel.provider == 'gowa'

    render json: { error: 'Esta caixa de entrada não usa GOWA.' }, status: :bad_request
  end

  def client
    @client ||= Gowa::Client.new(
      @inbox.channel.provider_config['gowa_base_url'],
      @inbox.channel.gowa_username,
      @inbox.channel.gowa_password
    )
  end

  def device_id
    @inbox.channel.provider_config.fetch('gowa_device_id')
  end

  def webhook_secret
    @inbox.channel.provider_config.fetch('webhook_secret')
  end

  def expected_webhook_url
    app_url = ENV['FRONTEND_URL'].presence || 'http://localhost:3000'
    "#{app_url}/webhooks/gowa/#{@inbox.id}"
  end

  def render_provider_error(error)
    Rails.logger.error "GOWA inbox #{@inbox.id}: #{error.message}"
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
