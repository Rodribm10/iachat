class Whatsapp::IncomingMessageWuzapiService < Whatsapp::IncomingMessageBaseService
  def perform
    # 1. Parse Payload
    # ----------------
    # Extract all necessary data from the WuzAPI webhook payload
    parser = Whatsapp::Providers::Wuzapi::PayloadParser.new(params)
    Rails.logger.info "WuzapiService: Processing #{parser.message_type} from #{parser.sender_phone_number}"

    # 2. Basic Validation
    # -------------------
    # Ignore statuses, presence updates, and errors for now
    if parser.message_type == :chat_presence || parser.message_type == :error || parser.message_type == :ignore
      Rails.logger.info "WuzAPI: Ignoring presence/error/ignore update (Type: #{parser.message_type})"
      return
    end

    allowed_types = [:text, :image, :audio, :video, :document, :sticker]
    unless allowed_types.include?(parser.message_type)
      Rails.logger.info(
        "WuzAPI: Unsupported message type: #{parser.message_type} " \
        "(webhook.type=#{params[:type]}, event.Info.Type=#{params.dig(:event, :Info, :Type)}, event.Type=#{params.dig(:event, :Type)})"
      )
      return
    end

    # 2.1 V1 Scope: Ignore Groups
    if parser.group_message?
      Rails.logger.info "WuzAPI: Ignoring group message (ID: #{parser.external_id})"
      return
    end

    if parser.sender_phone_number.blank? && !parser.from_me?
      Rails.logger.warn "WuzAPI: Skipping processing for event with no valid sender phone (Type: #{parser.message_type})"
      return
    end

    # 3. Strong Dedupe (Existing External ID)
    # ---------------------------------------
    # If we already have a message with this WAID, ignore it immediately.
    # This catches standard retries from WuzAPI or webhook re-deliveries.
    clean_source_id = "WAID:#{parser.external_id}"

    # 4. Find/Create Resources
    # ------------------------
    # Based on the sender (customer) or recipient (if it's a mobile reply)
    ActiveRecord::Base.transaction do
      # Strong dedupe inside transaction to prevent TOCTOU race condition
      if parser.external_id.present? && Message.exists?(source_id: clean_source_id, inbox_id: inbox.id)
        Rails.logger.info "WuzAPI: Ignoring duplicate message (ID: #{clean_source_id})"
        return
      end
      @contact = find_or_create_contact(parser)
      return if @contact.nil? # If contact couldn't be determined, stop processing

      @conversation = find_or_create_conversation(@contact, parser)

      # 5. Echo/AI Deduplication Logic
      # ------------------------------
      # If this is an outgoing message (from_me=true), it might be:
      # A) A reply sent from the physical phone (needs to be created as outgoing)
      # B) A confirmation echo of a message Chatwoot/AI just sent (needs to be merged)
      if parser.from_me?
        deduplicated_message = find_outgoing_message_to_deduplicate(parser, @conversation)
        if deduplicated_message
          # Merging logic: Update the local temporary message with the real WuzAPI ID
          Rails.logger.info "WuzAPI: Merging echo into existing message #{deduplicated_message.id}"
          deduplicated_message.update!(source_id: clean_source_id)
          return # Stop processing, we successfully merged.
        end
      end

      # 6. Create Message
      # -----------------
      # If it wasn't a duplicate, create the new message (Incoming or Outgoing)
      @message = build_message(parser, @conversation, clean_source_id)

      # Attach media BEFORE saving (Chatwoot pattern)
      attach_files(parser) if [:image, :audio, :video, :document, :sticker].include?(parser.message_type)

      # Now save with attachments
      @message.save!
      Rails.logger.info "WuzAPI: Message created: #{@message.id} (SourceID: #{clean_source_id})"
    end
  rescue StandardError => e
    Rails.logger.error "WuzAPI Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end

  private

  def find_or_create_contact(parser)
    # If from_me is true, the sender is US (the business).
    # The CONTACT for the conversation is properly the RECIPIENT (the customer).
    # If from_me is false, the sender is the CUSTOMER.
    phone_number = if parser.from_me?
                     parser.recipient_phone_number # Extracted from Chat ID
                   else
                     parser.sender_phone_number    # Extracted from Sender ID
                   end

    return nil if phone_number.blank?

    contact_inbox = ContactInbox.find_by(inbox_id: inbox.id, source_id: phone_number)
    return contact_inbox.contact if contact_inbox

    # Create or Find existing contact in the account
    # We use find_by to avoid uniqueness validation errors if the contact exists in another inbox
    formatted_phone = "+#{phone_number.to_s.delete('+')}"
    contact = inbox.account.contacts.find_by(phone_number: formatted_phone)

    contact ||= inbox.account.contacts.create!(
      name: parser.sender_name || phone_number,
      phone_number: formatted_phone,
      custom_attributes: { wuzapi_id: phone_number }
    )

    ContactInbox.create!(
      contact: contact,
      inbox: inbox,
      source_id: phone_number
    )

    contact
  end

  def find_or_create_conversation(contact, parser = nil)
    # Find the LAST open conversation for this contact to append to
    conversation = inbox.conversations.where(contact_id: contact.id)
                        .where.not(status: :resolved)
                        .order(updated_at: :desc)
                        .first

    return conversation if conversation

    # Find the ContactInbox association to linking
    contact_inbox = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id)

    # Build additional_attributes — include referral info from Click-to-WhatsApp ads if present
    extra_attrs = {}
    if parser
      referral = parser.referral_info
      if referral.present?
        # "referer" is the field Chatwoot automations use for "Link de origem" condition
        extra_attrs['referer'] = referral[:source_url].presence || 'meta_ads'
        extra_attrs['source_type'] = referral[:source_type] if referral[:source_type].present?
        extra_attrs['ctwa_clid'] = referral[:ctwa_clid] if referral[:ctwa_clid].present?
        Rails.logger.info "WuzAPI: Setting conversation referer='#{extra_attrs['referer']}' from ad referral"
      end
    end

    # If no open conversation, create a new one
    inbox.conversations.create!(
      contact: contact,
      contact_inbox: contact_inbox, # Explicitly required by Chatwoot validation
      status: :open,
      account_id: inbox.account_id,
      additional_attributes: extra_attrs
    )
  end

  def find_outgoing_message_to_deduplicate(parser, conversation)
    # We are looking for a message that:
    # 1. Is Outgoing (message_type: 1)
    # 2. Was created recently (e.g., last 2 minutes)
    # 3. Has NO source_id (it was created locally by AI/Agent without external ref yet)
    # 4. Has the SAME content as the webhook payload
    #
    # Note: Text matching can be fuzzy due to encoding/whitespace.
    # We compare stripped content.

    incoming_content = parser.text_content&.strip
    return nil if incoming_content.blank?

    # Time window to search back
    time_window = 5.minutes.ago

    conversation.messages.where(message_type: :outgoing, source_id: nil)
                .where('created_at > ?', time_window)
                .find { |msg| msg.content&.strip == incoming_content }
  end

  def build_message(parser, conversation, clean_source_id)
    is_outgoing = parser.from_me?

    msg_params = {
      content: parser.text_content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: is_outgoing ? :outgoing : :incoming,
      # If outgoing, sender is nil (system/agent). If incoming, sender is the contact.
      sender: is_outgoing ? nil : @contact,
      source_id: clean_source_id,
      created_at: parser.timestamp || Time.current
    }

    # Handle Replies
    # Handle Reply Logic (Aligned with Reference)
    if (reply_id = parser.in_reply_to_external_id).present?
      clean_reply_id = "WAID:#{reply_id}"

      # Strict lookup within conversation to prevent cross-inbox leaks
      original_message = conversation.messages.find_by(source_id: clean_reply_id)

      if original_message
        msg_params[:in_reply_to_id] = original_message.id
      else
        # Fallback: Store ID for UI "Replying to..." display even if not linked
        msg_params[:content_attributes] = { in_reply_to_external_id: clean_reply_id }
      end
    end

    # Use .build so we can attach files before .save!
    conversation.messages.build(msg_params)
  end

  def attach_files(parser)
    attachment_data = parser.attachment_params
    return if attachment_data.blank? || attachment_data[:external_url].blank?

    begin
      Rails.logger.info "WuzAPI: Processing attachment (URL: #{attachment_data[:external_url]}, File: #{attachment_data[:file_name]})"

      # 1. Download/Decrypt to get a file
      file_io = download_or_decrypt_media(attachment_data, parser.message_type)
      return if file_io.blank?

      # 2. Determine filename
      original_filename = attachment_data[:file_name] || "wuzapi_#{Time.now.to_i}"
      extension = File.extname(original_filename)
      extension = detect_extension(attachment_data[:mimetype], parser.message_type) if extension.blank?
      final_filename = "#{File.basename(original_filename, '.*')}#{extension}"

      # 3. Attach using Chatwoot's standard pattern
      @message.attachments.new(
        account_id: @message.account_id,
        file_type: file_content_type(parser.message_type),
        file: {
          io: file_io,
          filename: final_filename,
          content_type: attachment_data[:mimetype] || 'application/octet-stream'
        }
      )

      Rails.logger.info "WuzAPI: Attachment queued for save (#{final_filename})"

    rescue StandardError => e
      Rails.logger.error "WuzAPI Attachment Error: #{e.message}"
      Rails.logger.error e.backtrace.first(10).join("\n")
    end
  end

  def download_or_decrypt_media(attachment_data, message_type)
    media_url = attachment_data[:external_url]

    # METHOD 1: Use WuzAPI's /chat/downloadimage endpoint (returns DECRYPTED media)
    # This is the equivalent of Cloud API's media download
    begin
      Rails.logger.info 'WuzAPI: Attempting download via WuzAPI endpoint...'
      wuzapi_response = wuzapi_client.download_media(wuzapi_token, media_url)

      if wuzapi_response.is_a?(Hash) && wuzapi_response['data'].present?
        # WuzAPI returns base64 in 'data' field
        image_data = wuzapi_response['data']
        # Strip data URI prefix if present
        image_data = image_data.sub(/^data:.*?;base64,/, '') if image_data.start_with?('data:')

        decoded = Base64.decode64(image_data)
        if decoded.bytesize > 1000 # Valid image should be > 1KB
          Rails.logger.info 'WuzAPI: Download via endpoint SUCCESS'
          return StringIO.new(decoded)
        end
      end
    rescue StandardError => e
      Rails.logger.warn "WuzAPI: Endpoint download failed - #{e.message}"
    end

    # METHOD 2+3: Download from CDN (follows redirects) then decrypt if mediaKey available
    Rails.logger.info "WuzAPI: Downloading from CDN #{media_url}"
    encrypted_tempfile = Down.download(
      media_url,
      open_timeout: 10,
      read_timeout: 30,
      ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE
    )
    encrypted_bytes = encrypted_tempfile.read.b
    Rails.logger.info "WuzAPI: Downloaded #{encrypted_bytes.bytesize} bytes from CDN"

    if attachment_data[:media_key].present?
      Rails.logger.info 'WuzAPI: Attempting local decryption (mediaKey present)...'
      decrypted = Whatsapp::DecryptionService.new(
        attachment_data[:media_key],
        file_content_type(message_type)
      ).decrypt_bytes(encrypted_bytes)

      return decrypted if decrypted

      Rails.logger.warn 'WuzAPI: Local decryption failed, returning raw bytes'
    end

    StringIO.new(encrypted_bytes)
  rescue StandardError => e
    Rails.logger.error "WuzAPI: All download methods failed - #{e.message}"
    nil
  end

  def wuzapi_client
    @wuzapi_client ||= Wuzapi::Client.new(@inbox.channel.provider_config['wuzapi_base_url'])
  end

  def wuzapi_token
    @inbox.channel.wuzapi_user_token
  end

  def detect_extension(mimetype, message_type)
    return '.jpg' if message_type == :image || message_type == :sticker
    return '.mp3' if message_type == :audio
    return '.mp4' if message_type == :video

    case mimetype
    when 'image/png' then '.png'
    when 'image/webp' then '.webp'
    when 'image/gif' then '.gif'
    when 'audio/ogg' then '.ogg'
    when 'video/webm' then '.webm'
    else '.bin'
    end
  end

  def file_content_type(message_type)
    case message_type
    when :image, :sticker then :image
    when :audio then :audio
    when :video then :video
    else :file
    end
  end
end
