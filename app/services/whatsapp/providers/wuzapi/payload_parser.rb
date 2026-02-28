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

  include Whatsapp::Wuzapi::PayloadParserExtension

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
    msg = unwrap_ephemeral_message(params.dig(:event, :Message))
    return :text if params.dig(:event, :Text).present?
    return :unknown unless msg.is_a?(Hash)

    return :text if msg[:conversation].present? || msg[:extendedTextMessage].present?
    return :image if msg[:imageMessage].present?
    return :audio if msg[:audioMessage].present?
    return :video if msg[:videoMessage].present?
    return :sticker if msg[:stickerMessage].present?
    return :document if msg[:documentMessage].present? || msg[:documentWithCaptionMessage].present?

    :unknown
  end

  def unwrap_ephemeral_message(msg)
    return {} unless msg

    msg.key?(:ephemeralMessage) ? msg.dig(:ephemeralMessage, :message) : msg
  end

  def extract_jid
    if from_me?
      extract_recipient_jid
    else
      extract_sender_jid
    end
  end

  def extract_recipient_jid
    chat = params.dig(:event, :Info, :Chat) || params.dig(:event, :Chat)
    return chat if chat&.include?('@s.whatsapp.net')

    recipient_alt = params.dig(:event, :Info, :RecipientAlt) || params.dig(:event, :RecipientAlt)
    recipient_alt&.include?('@s.whatsapp.net') ? recipient_alt : chat
  end

  def extract_sender_jid
    sender = params.dig(:event, :Info, :Sender) || params.dig(:event, :Sender)
    sender_alt = params.dig(:event, :Info, :SenderAlt) || params.dig(:event, :SenderAlt)

    sender&.include?('@s.whatsapp.net') ? sender : (sender_alt || sender)
  end
end
