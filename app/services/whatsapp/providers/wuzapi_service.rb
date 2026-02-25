require_relative 'base_service'

class Whatsapp::Providers::WuzapiService < Whatsapp::Providers::BaseService
  attr_reader :whatsapp_channel

  def initialize(whatsapp_channel:)
    super(whatsapp_channel: whatsapp_channel)
    @base_url = whatsapp_channel.provider_config['wuzapi_base_url']
  end

  def send_message(phone_number, message)
    user_token = whatsapp_channel.wuzapi_user_token
    # Normalize phone number: remove +, space, -, (, )
    normalized_phone = phone_number.gsub(/[\+\s\-\(\)]/, '')

    Rails.logger.info "[WuzapiService] Sending Message:
      Message ID: #{message.id}
      Conversation ID: #{message.conversation_id}
      Contact Inbox ID: #{message.conversation.contact_inbox_id}
      Raw Phone (arg): #{phone_number}
      Normalized Phone (Target): #{normalized_phone}
      Content: #{message.content&.truncate(50)}
    "

    return send_reaction_message(normalized_phone, message) if message.content_attributes['is_reaction'] || message.content_attributes[:is_reaction]

    response = if message.attachments.present?
                 send_attachment_message(user_token, normalized_phone, message)
               else
                 params = {}
                 # Extract and clean reply ID (remove WAID: prefix if stored)
                 if (reply_id = message.content_attributes['in_reply_to_external_id']).present?
                   params['MessageId'] = reply_id.gsub(/^WAID:/, '')
                 elsif (reply_id = message.in_reply_to_external_id).present?
                   params['MessageId'] = reply_id.gsub(/^WAID:/, '')
                 end

                 client.send_text(user_token, normalized_phone, message.content, **params)
               end

    # Extract message ID from WuzAPI response and format as WAID:xxx
    extract_message_id(response)
  end

  def send_attachment_message(user_token, phone_number, message)
    attachment = message.attachments.first
    base64_data = Base64.strict_encode64(attachment.file.download)
    mime_type = attachment.file.content_type
    data_uri = "data:#{mime_type};base64,#{base64_data}"

    if mime_type.start_with?('image/')
      client.send_image(user_token, phone_number, data_uri, message.content)
    else
      client.send_file(user_token, phone_number, data_uri, attachment.file.filename.to_s)
    end
  end

  def send_reaction_message(phone_number, message)
    user_token = whatsapp_channel.wuzapi_user_token
    normalized_phone = phone_number.gsub(/[\+\s\-\(\)]/, '')

    # Assuming message content is the emoji
    reaction_emoji = message.content

    # Resolve the correct external message ID
    message_id = message.content_attributes['in_reply_to_external_id']

    # Fallback to internal ID resolution if external is missing
    if message_id.blank? && message.content_attributes['in_reply_to'].present?
      target_msg = message.conversation.messages.find_by(id: message.content_attributes['in_reply_to'])
      message_id = target_msg&.source_id
    end

    # Strip WAID prefix if present
    message_id = message_id.gsub(/^WAID:/, '') if message_id.present?

    use_me_prefix = reaction_to_own_message?(message)

    if use_me_prefix
      normalized_phone = "me:#{normalized_phone}" unless normalized_phone.start_with?('me:')
      message_id = "me:#{message_id}" if message_id.present? && !message_id.start_with?('me:')
    else
      # Enforce JID format for customer numbers
      clean_number = normalized_phone.split('@').first
      normalized_phone = "#{clean_number}@s.whatsapp.net"
    end

    Rails.logger.info "[WuzapiService] Attempting reaction: phone=#{normalized_phone}, msg_id=#{message_id}, emoji=#{reaction_emoji}"

    if message_id.present?
      # Wuzapi client needs to implement send_reaction
      # This assumes the client wrapper has this method. If not, we might need to add it or use raw request.
      # Based on typical Wuzapi forks, it might be /send-reaction-message

      # We'll assume the client wrapper will have a send_reaction method.
      # If not visible in the existing codebase, we might need to add it to the client class too.
      # checking...
      response = client.send_reaction(user_token, normalized_phone, message_id, reaction_emoji)
      Rails.logger.info "[WuzapiService] Reaction response: #{response}"
      response
    else
      Rails.logger.warn 'Wuzapi: Cannot send reaction without in_reply_to message ID'
    end
  end

  def send_template(_phone_number, _template_info)
    # Placeholder for template support if Wuzapi supports it.
    # For now, just logging or no-op as per initial text-focused plan.
    Rails.logger.warn 'Wuzapi: Templates not yet implemented or supported.'
  end

  def sync_templates
    # No-op for Wuzapi as it doesn't insist on syncing templates like Cloud API
  end

  def validate_provider_config?
    # Validate if we can connect to session status
    user_token = whatsapp_channel.wuzapi_user_token
    return false if user_token.blank?

    begin
      client.session_status(user_token)
      true
    rescue Wuzapi::Client::Error
      false
    end
  end

  def toggle_typing_status(typing_status, recipient_id: nil, **_kwargs)
    # typing_status: 'typing_on', 'typing_off'
    # Wuzapi expects: 'composing', 'paused'

    state = %w[typing_on on].include?(typing_status) ? 'composing' : 'paused'
    user_token = whatsapp_channel.wuzapi_user_token
    phone_number = recipient_id || whatsapp_channel.phone_number

    # Clean phone number (digits only)
    normalized_phone = phone_number.to_s.gsub(/[\+\s\-\(\)]/, '')

    # Enforce JID format: 5561...@s.whatsapp.net
    # Strip any existing suffix (like @lid or even @s.whatsapp.net to be safe) and append standard one.
    clean_number = normalized_phone.split('@').first
    jid = "#{clean_number}@s.whatsapp.net"

    Rails.logger.info "[WuzapiService] toggle_typing_status: Sending presence to #{jid} (raw: #{normalized_phone}), state: #{state}, token_present: #{user_token.present?}"

    begin
      # Use JID in the 'Phone' field as confirmed by manual tests (Test C)
      response = client.send_chat_presence(user_token, jid, state)
      Rails.logger.info "[WuzapiService] toggle_typing_status response: #{response}"
    rescue StandardError => e
      Rails.logger.warn "Wuzapi: Failed to send typing status: #{e.message}"
    end
  end

  private

  def client
    @client ||= ::Wuzapi::Client.new(@base_url)
  end

  # Extract message ID from WuzAPI response and format it as WAID:xxx
  # WuzAPI returns: {"code" => 200, "data" => {"Id" => "xxx", ...}, "success" => true}
  def extract_message_id(response)
    return nil unless response.is_a?(Hash)

    message_id = response.dig('data', 'Id') || response.dig(:data, :Id)
    return nil if message_id.blank?

    "WAID:#{message_id}"
  end

  def reaction_to_own_message?(message)
    # If we can resolve the target message, check if it was sent by us.
    target_message = nil
    if message.in_reply_to.present?
      target_message = message.conversation.messages.find_by(id: message.in_reply_to)
      target_message ||= message.conversation.messages.find_by(source_id: message.in_reply_to)
    elsif message.in_reply_to_external_id.present?
      target_message = message.conversation.messages.find_by(source_id: message.in_reply_to_external_id)
    end

    return false if target_message.blank?

    target_message.outgoing? || target_message.template?
  end
end
