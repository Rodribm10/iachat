class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  def process_payload
    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    perform_whatsapp_events_job
  end

  private

  def perform_whatsapp_events_job
    if ignorable_wuzapi_status_event?
      Rails.logger.info("Ignoring WuzAPI status broadcast event for #{params[:phone_number]}")
      head :ok
      return
    end

    perform_sync if params[:awaitResponse].present?
    return if performed?

    Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  def perform_sync
    Webhooks::WhatsappEventsJob.perform_now(params.to_unsafe_hash)
  rescue Whatsapp::IncomingMessageBaileysService::InvalidWebhookVerifyToken
    head :unauthorized
  rescue Whatsapp::IncomingMessageBaileysService::MessageNotFoundError
    head :not_found
  end

  def valid_token?(token)
    channel = find_channel_by_phone_number(params[:phone_number])
    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
  end

  def inactive_whatsapp_number?
    phone_number = normalize_phone(params[:phone_number])
    return false if phone_number.blank?

    inactive_numbers = GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s
    return false if inactive_numbers.blank?

    inactive_numbers_array = inactive_numbers.split(',').map(&:strip)
    inactive_numbers_array.map { |number| normalize_phone(number) }.include?(phone_number)
  end

  def find_channel_by_phone_number(phone_number)
    raw_phone = phone_number.to_s.strip
    digits_only = normalize_phone(raw_phone)
    return if raw_phone.blank? && digits_only.blank?

    Channel::Whatsapp.find_by(phone_number: raw_phone) ||
      Channel::Whatsapp.find_by(phone_number: "+#{digits_only}") ||
      Channel::Whatsapp.where("regexp_replace(phone_number, '[^0-9]', '', 'g') = ?", digits_only).first
  end

  def normalize_phone(phone_number)
    phone_number.to_s.gsub(/\D/, '')
  end

  def ignorable_wuzapi_status_event?
    params[:type].to_s == 'Message' &&
      (params.dig(:event, :Info, :Chat).to_s == 'status@broadcast' ||
        params.dig(:event, :Chat).to_s == 'status@broadcast')
  end
end
