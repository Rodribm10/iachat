class Whatsapp::Providers::Wuzapi::PayloadParser
  attr_reader :params

  def initialize(params)
    @params = params.with_indifferent_access
  end

  def external_id
    params.dig(:event, :Info, :ID)
  end

  def from_me?
    # A flag comes primarily from 'IsFromMe' or nested in 'Info'
    is_api_from_me = params.dig(:event, :Info, :IsFromMe) || params.dig(:event, :IsFromMe)

    # However, WuzAPI might be inconsistent. We also check if the sender matches the instance phone.
    # But if the API explicitly says "IsFromMe: true", we trust it first.
    return true if is_api_from_me.present? && is_api_from_me.to_s == 'true'

    # Fallback check: Sender JID prefix matches instance phone number
    instance_phone = params['phone_number']
    sender_jid = params.dig(:event, :Info, :Sender) || params.dig(:event, :Sender)

    if instance_phone.present? && sender_jid.present?
      sender_phone = sender_jid.split('@').first
      return true if sender_phone == instance_phone
    end

    false
  end

  # Extracts the CUSTOMER phone number when the message is FROM ME (outgoing).
  # In this case, the 'Chat' field contains the recipient (customer) JID.
  # When WuzAPI uses LIDs, we fallback to RecipientAlt which has the real number.
  def recipient_phone_number
    chat_id = params.dig(:event, :Info, :Chat) || params.dig(:event, :Chat)

    # If Chat is a real number, use it
    return chat_id.split('@').first.split(':').first if chat_id&.include?('@s.whatsapp.net')

    # Fallback to RecipientAlt when Chat uses LID format
    recipient_alt = params.dig(:event, :Info, :RecipientAlt) || params.dig(:event, :RecipientAlt)
    return recipient_alt.split('@').first.split(':').first if recipient_alt&.include?('@s.whatsapp.net')

    nil
  end

  def message_type
    return :chat_presence if webhook_event_type == 'ChatPresence'
    return :ignore if ignorable_webhook_event_type?

    # Info: Type contains the general classification (text, image, etc)
    type = raw_info_type.to_s.downcase
    media_type = params.dig(:event, :Info, :MediaType).to_s.downcase

    # WuzAPI sometimes sends 'media' in Type and the actual type in MediaType
    type = media_type if type == 'media' && media_type.present?

    case type
    when 'text' then :text
    when 'image' then :image
    when 'audio' then :audio
    when 'video' then :video
    when 'document' then :document
    when 'sticker' then :sticker
    when 'readreceipt' then :ignore
    else
      fallback_message_type_from_payload
    end
  end

  def presence_state
    params.dig(:event, :State)
  end

  def in_reply_to_external_id
    msg = unwrap_ephemeral_message(params.dig(:event, :Message))
    return nil unless msg.is_a?(Hash)

    # DEBUG: Log the message structure to understand reply context
    Rails.logger.info "WuzAPI Reply Debug: Message keys = #{msg.keys.inspect}"

    # 1. Extended text
    ctx = msg.dig(:extendedTextMessage, :contextInfo)
    if ctx.present?
      Rails.logger.info "WuzAPI Reply Debug: Found extendedTextMessage contextInfo = #{ctx.inspect}"
      stanza = ctx[:stanzaID] || ctx[:stanzaId]
      return stanza if stanza.present?
    end

    # 2. Media Types direct contextInfo
    [:imageMessage, :videoMessage, :audioMessage, :stickerMessage, :documentMessage].each do |key|
      ctx = msg.dig(key, :contextInfo)
      next if ctx.blank?

      Rails.logger.info "WuzAPI Reply Debug: Found #{key} contextInfo = #{ctx.inspect}"
      stanza = ctx[:stanzaID] || ctx[:stanzaId]
      return stanza if stanza.present?
    end

    # 3. Document With Caption
    if msg.key?(:documentWithCaptionMessage)
      ctx = msg.dig(:documentWithCaptionMessage, :message, :documentMessage, :contextInfo)
      if ctx.present?
        Rails.logger.info "WuzAPI Reply Debug: Found documentWithCaptionMessage contextInfo = #{ctx.inspect}"
        return ctx[:stanzaID] || ctx[:stanzaId]
      end
    end

    # 4. Check for simple conversation with contextInfo (text reply without extendedTextMessage)
    if msg[:conversation].present? && msg[:contextInfo].present?
      ctx = msg[:contextInfo]
      Rails.logger.info "WuzAPI Reply Debug: Found conversation contextInfo = #{ctx.inspect}"
      stanza = ctx[:stanzaID] || ctx[:stanzaId]
      return stanza if stanza.present?
    end

    Rails.logger.info 'WuzAPI Reply Debug: No reply context found'
    nil
  end

  def text_content
    msg = unwrap_ephemeral_message(params.dig(:event, :Message))
    # Legacy fallback used by some WuzAPI payload variants
    return params.dig(:event, :Text) if params.dig(:event, :Text).present?
    return nil unless msg.is_a?(Hash)

    # 1. Simple text
    return msg[:conversation] if msg[:conversation].present?

    # 2. Extended Text
    return msg.dig(:extendedTextMessage, :text) if msg.dig(:extendedTextMessage, :text).present?

    # 3. Media Captions (Image, Video, Document)
    [:imageMessage, :videoMessage, :documentMessage].each do |media_key|
      caption = msg.dig(media_key, :caption)
      return caption if caption.present?
    end

    # 4. Document With Caption
    return msg.dig(:documentWithCaptionMessage, :message, :documentMessage, :caption) if msg.key?(:documentWithCaptionMessage)

    nil
  end

  def attachment_params
    media_key = case message_type
                when :image then :imageMessage
                when :audio then :audioMessage
                when :video then :videoMessage
                when :document then :documentMessage
                when :sticker then :stickerMessage
                end
    return nil unless media_key

    msg = unwrap_ephemeral_message(params.dig(:event, :Message))
    data = msg[media_key]
    return nil unless data.is_a?(Hash)

    {
      external_url: data['URL'],
      file_name: data['fileName'] || "file_#{external_id}",
      mimetype: data['mimetype'],
      thumbnail: data['JPEGThumbnail'],
      media_key: data['mediaKey']
    }
  end

  # Returns referral/ad tracking info for Click-to-WhatsApp Meta Ads messages.
  # WuzAPI/whatsmeow may include this in extendedTextMessage.contextInfo.externalAdReply
  # or via Info.Category = "business". Returns nil if no referral data found.
  def referral_info
    msg = unwrap_ephemeral_message(params.dig(:event, :Message))

    # Check externalAdReply in extendedTextMessage (Click-to-WhatsApp ad flow)
    if msg.is_a?(Hash)
      ad_reply = msg.dig(:extendedTextMessage, :contextInfo, :externalAdReply)
      ad_reply ||= msg.dig('extendedTextMessage', 'contextInfo', 'externalAdReply')

      if ad_reply.is_a?(Hash) && ad_reply.present?
        Rails.logger.info "WuzAPI: Click-to-WhatsApp referral detected: #{ad_reply.inspect}"
        return {
          source_url: ad_reply['sourceUrl'] || ad_reply[:sourceUrl],
          source_id: ad_reply['sourceId'] || ad_reply[:sourceId],
          source_type: 'ad',
          ctwa_clid: ad_reply['ctwaClid'] || ad_reply[:ctwaClid],
          headline: ad_reply['title'] || ad_reply[:title],
          body: ad_reply['body'] || ad_reply[:body]
        }
      end
    end

    # Check Info.Category — some WuzAPI versions mark business-initiated as "business"
    category = params.dig(:event, :Info, :Category).to_s.downcase
    if category == 'business'
      Rails.logger.info 'WuzAPI: Business category message detected (possible CTWA ad)'
      return { source_type: 'ad', source_url: nil }
    end

    nil
  end

  def sender_phone_number
    jid = extract_jid

    # Reject LIDs as they aren't valid E164 phone numbers
    return nil if jid.blank? || jid.include?('@lid')

    # Format: 556182098580:1@s.whatsapp.net -> 556182098580
    # MD accounts include a device index suffix (eg. :1) that we must strip
    jid.split('@').first.split(':').first
  end

  def timestamp
    timestamp_val = params.dig(:event, :Info, :Timestamp) || params.dig(:event, :Timestamp)
    return Time.current if timestamp_val.blank?

    begin
      Time.zone.parse(timestamp_val.to_s)
    rescue ArgumentError
      Time.current
    end
  end

  def sender_name
    params.dig(:event, :Info, :PushName) || params.dig(:event, :PushName)
  end

  def group_message?
    params.dig(:event, :Info, :IsGroup) || params.dig(:event, :IsGroup)
  end

  private

  def webhook_event_type
    params[:type].to_s
  end

  def raw_info_type
    params.dig(:event, :Info, :Type) || params.dig(:event, :Type)
  end

  def ignorable_webhook_event_type?
    # These are provider/system updates and should not be treated as incoming user messages.
    ignorable = %w[
      ReadReceipt
      UserAbout
      IdentityChange
      Picture
      Connected
      Disconnected
      OfflineSyncCompleted
      Presence
      PresenceUpdate
      Ack
    ]

    ignorable.include?(webhook_event_type)
  end

  def fallback_message_type_from_payload
    # Fallback: detect type from message body shape, even when Info.Type is missing or inconsistent.
    msg = unwrap_ephemeral_message(params.dig(:event, :Message))

    if msg.is_a?(Hash)
      return :text if msg[:conversation].present? || msg[:extendedTextMessage].present? || msg.dig(:extendedTextMessage, :text).present?
      return :image if msg[:imageMessage].present?
      return :audio if msg[:audioMessage].present?
      return :video if msg[:videoMessage].present?
      return :document if msg[:documentMessage].present? || msg[:documentWithCaptionMessage].present?
      return :sticker if msg[:stickerMessage].present?
    end

    return :text if params.dig(:event, :Text).present?

    :unknown
  end

  def unwrap_ephemeral_message(msg)
    return {} unless msg

    msg.key?(:ephemeralMessage) ? msg.dig(:ephemeralMessage, :message) : msg
  end

  def extract_jid
    if from_me?
      # For outgoing messages, prefer Chat if it's a real number
      chat = params.dig(:event, :Info, :Chat) || params.dig(:event, :Chat)
      return chat if chat&.include?('@s.whatsapp.net')

      # Fallback to RecipientAlt when Chat uses LID format
      recipient_alt = params.dig(:event, :Info, :RecipientAlt) || params.dig(:event, :RecipientAlt)
      return recipient_alt if recipient_alt&.include?('@s.whatsapp.net')

      chat # Return original Chat even if LID (will be filtered later)
    else
      sender = params.dig(:event, :Info, :Sender) || params.dig(:event, :Sender)
      sender_alt = params.dig(:event, :Info, :SenderAlt) || params.dig(:event, :SenderAlt)

      # Prefer @s.whatsapp.net over @lid
      if sender&.include?('@s.whatsapp.net')
        sender
      elsif sender_alt&.include?('@s.whatsapp.net')
        sender_alt
      else
        sender
      end
    end
  end
end
