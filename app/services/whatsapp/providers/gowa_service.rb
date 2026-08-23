class Whatsapp::Providers::GowaService < Whatsapp::Providers::BaseService
  def send_message(phone_number, message)
    response = if message.attachments.present?
                 client.send_attachment(
                   device_id,
                   phone_number,
                   message.attachments.first,
                   caption: normalize_whatsapp_markdown(message.content),
                   reply_message_id: reply_message_id(message)
                 )
               else
                 client.send_text(device_id, phone_number, normalize_whatsapp_markdown(message.content), reply_message_id: reply_message_id(message))
               end

    message_id = response.dig('results', 'id') || response.dig('results', 'message_id')
    message_id.present? ? "GOWA:#{message_id}" : nil
  end

  def send_template(_phone_number, _template_info)
    Rails.logger.warn 'GOWA não suporta templates do WhatsApp Business.'
  end

  def sync_templates; end

  def validate_provider_config?
    client.device_status(device_id)
    true
  rescue Gowa::Client::Error, ArgumentError
    false
  end

  def toggle_typing_status(typing_status, recipient_id: nil, **_kwargs)
    state = %w[typing_on on].include?(typing_status) ? 'composing' : 'paused'
    client.send_presence(device_id, recipient_id, state)
  rescue Gowa::Client::Error => e
    Rails.logger.warn "GOWA: não foi possível atualizar o indicador de digitação: #{e.message}"
  end

  private

  def client
    @client ||= Gowa::Client.new(
      whatsapp_channel.provider_config['gowa_base_url'],
      whatsapp_channel.gowa_username,
      whatsapp_channel.gowa_password
    )
  end

  def device_id
    whatsapp_channel.provider_config.fetch('gowa_device_id')
  end

  def reply_message_id(message)
    message.in_reply_to_external_id.to_s.delete_prefix('GOWA:').presence
  end
end
