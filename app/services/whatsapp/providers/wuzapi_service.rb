require_relative 'base_service'

class Whatsapp::Providers::WuzapiService < Whatsapp::Providers::BaseService
  attr_reader :whatsapp_channel

  def initialize(whatsapp_channel:)
    super(whatsapp_channel: whatsapp_channel)
    @base_url = whatsapp_channel.provider_config['wuzapi_base_url']
  end

  def send_message(phone_number, message)
    user_token = whatsapp_channel.wuzapi_user_token
    normalized_phone = normalize_phone(phone_number)
    log_outgoing_message(message)
    return send_reaction_message(normalized_phone, message) if reaction_message?(message)

    content_to_send = build_content_with_signature(message)
    response = dispatch_message(user_token, normalized_phone, message, content_to_send)
    extract_message_id(response)
  end

  def send_attachment_message(user_token, phone_number, message, content_with_signature = nil)
    attachment = message.attachments.first
    mime_type = attachment.file.content_type
    caption = content_with_signature || message.content

    base64_data = attachment.file.blob.open { |tmp| Base64.strict_encode64(tmp.read) }
    data_uri = "data:#{mime_type};base64,#{base64_data}"

    if mime_type.start_with?('image/')
      client.send_image(user_token, phone_number, data_uri, caption)
    else
      client.send_file(user_token, phone_number, data_uri, attachment.file.filename.to_s)
    end
  end

  def send_reaction_message(phone_number, message)
    user_token  = whatsapp_channel.wuzapi_user_token
    reaction_emoji = message.content
    message_id  = resolve_reaction_message_id(message)
    phone, mid  = build_reaction_targets(phone_number, message_id, message)

    Rails.logger.info "[WuzapiService] Attempting reaction: phone=#{phone}, msg_id=#{mid}, emoji=#{reaction_emoji}"

    if mid.blank?
      Rails.logger.warn 'Wuzapi: Cannot send reaction without in_reply_to message ID'
      return
    end

    response = client.send_reaction(user_token, phone, mid, reaction_emoji)
    Rails.logger.info "[WuzapiService] Reaction response: #{response}"
    response
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

  def normalize_phone(phone_number)
    phone_number.gsub(/[+\s\-()]/, '')
  end

  def reaction_message?(message)
    message.content_attributes['is_reaction'] || message.content_attributes[:is_reaction]
  end

  def log_outgoing_message(message)
    Rails.logger.info "[WuzapiService] Sending Message: ID=#{message.id} Conv=#{message.conversation_id} Content=#{message.content&.truncate(50)}"
  end

  def sender_name_for(message)
    agent = message.sender
    if agent.is_a?(User)
      agent.display_name.presence || agent.name
    elsif agent.is_a?(Captain::Assistant)
      agent.name
    else
      message.inbox.shift_signature_name
    end
  end

  def build_content_with_signature(message)
    content = message.content
    return content unless message.inbox.message_signature_enabled?

    name = sender_name_for(message)
    name.present? ? "*[ #{name} ]*\n#{content}" : content
  end

  def reply_params(message)
    params = {}
    reply_id = message.content_attributes['in_reply_to_external_id'].presence ||
               message.in_reply_to_external_id.presence
    params['MessageId'] = reply_id.gsub(/^WAID:/, '') if reply_id
    params
  end

  def dispatch_message(user_token, phone, message, content)
    if message.attachments.present?
      send_attachment_message(user_token, phone, message, content)
    else
      client.send_text(user_token, phone, content, **reply_params(message))
    end
  end

  def resolve_reaction_message_id(message)
    mid = message.content_attributes['in_reply_to_external_id']
    if mid.blank? && message.content_attributes['in_reply_to'].present?
      target = message.conversation.messages.find_by(id: message.content_attributes['in_reply_to'])
      mid = target&.source_id
    end
    mid.present? ? mid.gsub(/^WAID:/, '') : nil
  end

  def build_reaction_targets(phone_number, message_id, message)
    phone = normalize_phone(phone_number)
    mid   = message_id
    if reaction_to_own_message?(message)
      phone = "me:#{phone}" unless phone.start_with?('me:')
      mid   = "me:#{mid}" if mid.present? && !mid.start_with?('me:')
    else
      phone = "#{phone.split('@').first}@s.whatsapp.net"
    end
    [phone, mid]
  end

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
