class Api::V1::Accounts::Inboxes::WuzapiController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :ensure_wuzapi_provider

  def show
    # Session Status

    status_data = client.session_status(user_token)
    # Wuzapi returns nested data: { data: { connected: true, jid: "..." } }
    # Pass it through to frontend for validation
    render json: status_data
  rescue Wuzapi::Client::Error => e
    Rails.logger.error "Wuzapi Status Error: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "Wuzapi Status Critical Error: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  def qr
    # Get QR Code

    # Check status first to avoid error if already connected
    status_data = client.session_status(user_token)
    # Wuzapi status can be string or object with 'status'/'state'
    status = status_data['status'] || status_data['state'] || status_data
    Rails.logger.info "Wuzapi Connect/QR Flow - Current Status: #{status}"

    return if already_connected?(status)

    qr_data = client.get_qr_code(user_token)
    log_qr_data_keys(qr_data)
    render json: qr_data
  rescue Wuzapi::Client::Error => e
    Rails.logger.error "Wuzapi QR Error: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "Wuzapi QR Critical Error: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  def connect
    # Trigger connection (if needed by Wuzapi flow)

    result = client.session_connect(user_token)
    render json: result
  rescue Wuzapi::Client::Error => e
    # Idempotency: "already connected" is a success state
    if e.message.include?('already connected')
      render json: { success: true, message: 'Already connected' }, status: :ok
    else
      Rails.logger.error "Wuzapi Connect Error: #{e.message}"
      render json: { error: e.message }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "Wuzapi Connect Critical Error: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  def disconnect
    # Disconnect session

    result = client.session_logout(user_token) || client.session_disconnect(user_token)
    render json: result
  rescue Wuzapi::Client::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  def webhook_info
    info = client.get_webhook(user_token)
    render json: info
  rescue Wuzapi::Client::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  def update_webhook
    # Re-calculate correct webhook URL from model
    url = @inbox.channel.webhook_url
    client.update_webhook(user_token, url)
    render json: { success: true, message: 'Webhook updated successfully', webhook_url: url }
  rescue Wuzapi::Client::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def ensure_wuzapi_provider
    return if @inbox.channel.provider == 'wuzapi'

    render json: { error: 'Not a Wuzapi inbox' }, status: :bad_request
  end

  def client
    @client ||= Wuzapi::Client.new(@inbox.channel.provider_config['wuzapi_base_url'])
  end

  def user_token
    token = @inbox.channel.wuzapi_user_token
    if token.blank?
      Rails.logger.error "Wuzapi Token Missing for Inbox #{@inbox.id}"
      raise 'Token Wuzapi ausente; reprovisionar usuário'
    else
      Rails.logger.info "Wuzapi Request using Token (last 6): ******#{token.to_s[-6..]}"
    end
    token
  end

  def already_connected?(status)
    if %w[CONNECTED inChat success].include?(status)
      Rails.logger.info 'Wuzapi is already connected. Skipping QR.'
      render json: { qrcode: nil, status: 'CONNECTED', message: 'Already connected' }
      true
    else
      false
    end
  end

  def log_qr_data_keys(qr_data)
    Rails.logger.info "Wuzapi QR Data Response keys: #{qr_data.keys}"
  rescue StandardError
    Rails.logger.info 'Wuzapi QR Data Response keys: nil'
  end
end
