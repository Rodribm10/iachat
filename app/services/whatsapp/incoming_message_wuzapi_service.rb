class Whatsapp::IncomingMessageWuzapiService < Whatsapp::IncomingMessageBaseService
  include Whatsapp::Wuzapi::PayloadParserExtension

  def perform
    @parser = Whatsapp::Providers::Wuzapi::PayloadParser.new(params)
    return if ignore_message?

    @clean_source_id = "WAID:#{@parser.external_id}"
    ActiveRecord::Base.transaction do
      return if duplicate?

      process_incoming_payload
    end
  rescue StandardError => e
    log_error(e)
    raise e
  end

  private

  def ignore_message?
    return true if @parser.message_type == :chat_presence || @parser.message_type == :error || @parser.message_type == :ignore
    return true unless [:text, :image, :audio, :video, :document, :sticker].include?(@parser.message_type)
    return true if @parser.group_message?
    return true if @parser.sender_phone_number.blank? && !@parser.from_me?

    false
  end

  def duplicate?
    return false if @parser.external_id.blank?
    return false unless Message.exists?(source_id: @clean_source_id, inbox_id: inbox.id)

    Rails.logger.info "WuzAPI: Ignoring duplicate message (ID: #{@clean_source_id})"
    true
  end

  def process_incoming_payload
    @contact = find_or_create_contact
    return if @contact.nil?

    @conversation = find_or_create_conversation

    return if @parser.from_me? && handle_echo_message

    create_new_message
  end

  def handle_echo_message
    deduplicated_message = find_outgoing_message_to_deduplicate(@parser, @conversation)
    return false unless deduplicated_message

    Rails.logger.info "WuzAPI: Merging echo into existing message #{deduplicated_message.id}"
    deduplicated_message.update!(source_id: @clean_source_id)
    true
  end

  def create_new_message
    @message = build_message(@parser, @conversation, @clean_source_id)
    attach_files if [:image, :audio, :video, :document, :sticker].include?(@parser.message_type)
    @message.save!
    Rails.logger.info "WuzAPI: Message created: #{@message.id} (SourceID: #{@clean_source_id})"
  end

  def log_error(error)
    Rails.logger.error "WuzAPI Error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
  end

  def find_or_create_contact
    phone_number = @parser.from_me? ? @parser.recipient_phone_number : @parser.sender_phone_number
    return nil if phone_number.blank?

    contact_inbox = ContactInbox.find_by(inbox_id: inbox.id, source_id: phone_number)
    return contact_inbox.contact if contact_inbox

    contact = find_existing_contact(phone_number)
    contact ||= create_contact(phone_number)

    create_contact_inbox(contact, phone_number)
    contact
  end

  def find_existing_contact(phone_number)
    formatted_phone = "+#{phone_number.to_s.delete('+')}"
    inbox.account.contacts.find_by(phone_number: formatted_phone)
  end

  def create_contact(phone_number)
    formatted_phone = "+#{phone_number.to_s.delete('+')}"
    inbox.account.contacts.create!(
      name: @parser.sender_name || phone_number,
      phone_number: formatted_phone,
      custom_attributes: { wuzapi_id: phone_number }
    )
  end

  def create_contact_inbox(contact, phone_number)
    ContactInbox.create!(contact: contact, inbox: inbox, source_id: phone_number)
  end

  def find_or_create_conversation
    conversation = inbox.conversations.where(contact_id: @contact.id)
                        .where.not(status: :resolved)
                        .order(updated_at: :desc).first

    return conversation if conversation

    contact_inbox = ContactInbox.find_by(contact_id: @contact.id, inbox_id: inbox.id)
    inbox.conversations.create!(
      contact: @contact,
      contact_inbox: contact_inbox,
      status: :open,
      account_id: inbox.account_id,
      additional_attributes: conversation_attributes
    )
  end

  def conversation_attributes
    referral = @parser.referral_info
    return {} if referral.blank?

    {
      'referer' => referral[:source_url].presence || 'meta_ads',
      'source_type' => referral[:source_type],
      'ctwa_clid' => referral[:ctwa_clid]
    }.compact
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
      account_id: inbox.account_id, inbox_id: inbox.id,
      message_type: is_outgoing ? :outgoing : :incoming,
      sender: is_outgoing ? nil : @contact,
      source_id: clean_source_id,
      created_at: parser.timestamp || Time.current
    }

    add_reply_to_params(msg_params, parser, conversation)
    conversation.messages.build(msg_params)
  end

  def add_reply_to_params(params, parser, conversation)
    reply_id = parser.in_reply_to_external_id
    return if reply_id.blank?

    clean_reply_id = "WAID:#{reply_id}"
    original_message = conversation.messages.find_by(source_id: clean_reply_id)

    if original_message
      params[:in_reply_to_id] = original_message.id
    else
      params[:content_attributes] = { in_reply_to_external_id: clean_reply_id }
    end
  end

  def attach_files
    @attachment_data = @parser.attachment_params
    return if @attachment_data.blank? || @attachment_data[:external_url].blank?

    Whatsapp::Wuzapi::MediaHandler.new(inbox, @parser).process(@message, @attachment_data)
  rescue StandardError => e
    log_attachment_error(e)
  end

  def log_attachment_error(error)
    Rails.logger.error "WuzAPI Attachment Error: #{error.message}"
    Rails.logger.error error.backtrace.first(10).join("\n")
  end
end
