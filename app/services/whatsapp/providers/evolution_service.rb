require_relative 'base_service'

class Whatsapp::Providers::EvolutionService < Whatsapp::Providers::BaseService
  attr_reader :whatsapp_channel

  def initialize(whatsapp_channel:)
    super(whatsapp_channel: whatsapp_channel)
    @base_url = whatsapp_channel.provider_config['evolution_base_url']
    @api_token = whatsapp_channel.evolution_api_token
  end

  def send_message(phone_number, message)
    # Normalize phone number: remove +, space, -, (, )
    normalized_phone = phone_number.gsub(/[\+\s\-\(\)]/, '')

    instance_name = "Chatwoot_#{whatsapp_channel.phone_number}"

    Rails.logger.info "[EvolutionService] Sending Message:
      Message ID: #{message.id}
      Raw Phone: #{phone_number}
      Normalized Phone: #{normalized_phone}
    "

    # Se a mensagem tiver anexo, usamos send_attachment_message.
    response = if message.attachments.present?
                 send_attachment_message(instance_name, normalized_phone, message)
               else
                 params = {}
                 if (reply_id = message.content_attributes['in_reply_to_external_id']).present?
                   # Normalmente as bibliotecas WA recebem um ID p/ quote, isso depende muito da lib Go (que repassa a stanza p/ multidevice)
                   params['quoted'] = { key: { id: reply_id } }
                 end

                 client.send_text(instance_name, normalized_phone, message.content, **params)
               end

    extract_message_id(response)
  end

  def send_attachment_message(instance_name, phone_number, message)
    attachment = message.attachments.first

    # Verifica o env se estamos servindo de S3 ou local
    # Dependendo da lib Evolution, ele aceita URL ou Base64. Vamos usar Base64 para ser seguro pareado c/ local ou nuvem.
    begin
      base64_data = Base64.strict_encode64(attachment.file.download)
      mime_type = attachment.file.content_type
      data_uri = "data:#{mime_type};base64,#{base64_data}"

      if mime_type.start_with?('image/')
        client.send_image(instance_name, phone_number, data_uri, message.content)
      else
        client.send_file(instance_name, phone_number, data_uri, attachment.file.filename.to_s)
      end
    rescue StandardError => e
      Rails.logger.error "[EvolutionService] Attachment Error: #{e.message}"
      nil
    end
  end

  def send_template(_phone_number, _template_info)
    Rails.logger.warn 'Evolution: Templates not yet implemented or supported.'
  end

  def sync_templates
    # No-op
  end

  def validate_provider_config?
    return false if @api_token.blank? || @base_url.blank?

    instance_name = "Chatwoot_#{whatsapp_channel.phone_number}"

    begin
      client.session_status(instance_name)
      true
    rescue EvolutionApi::Client::Error
      false
    end
  end

  # Podemos adicionar toggle_typing_status futuramente caso precisemos e a rota exista.
  def toggle_typing_status(_typing_status, recipient_id: nil, **_kwargs)
    nil
  end

  private

  def client
    @client ||= ::EvolutionApi::Client.new(@base_url, @api_token)
  end

  def extract_message_id(response)
    return nil unless response.is_a?(Hash)

    # Baseado nas respostas de serviços baileys-like, key id costuma vir na msg.
    # Pode variar de {"key"=>{"id"=> "..."}} até {"id": "..."} na raiz
    message_id = response.dig('message', 'key', 'id') || response.dig('key', 'id') || response['id']
    return nil if message_id.blank?

    message_id
  end
end
