require 'stringio'

class Whatsapp::IncomingMessageGowaService
  pattr_initialize [:inbox!, :params!]

  def perform
    return unless params['event'] == 'message'
    return if group_or_system_message?
    return if external_id.blank? || contact_phone.blank?
    return if Message.exists?(source_id: source_id, inbox_id: inbox.id)

    ActiveRecord::Base.transaction do
      contact_inbox = find_or_create_contact_inbox
      conversation = find_or_create_conversation(contact_inbox)
      next if from_me? && merge_outgoing_echo(conversation)

      message = conversation.messages.build(message_attributes)
      attach_media(message)
      message.save!
    end
  end

  private

  def payload
    @payload ||= params.fetch('payload', {}).with_indifferent_access
  end

  def external_id
    payload[:id]
  end

  def source_id
    "GOWA:#{external_id}"
  end

  def from_me?
    payload[:is_from_me] == true
  end

  def group_or_system_message?
    chat_id = payload[:chat_id].to_s
    chat_id.end_with?('@g.us', '@newsletter') || chat_id == 'status@broadcast'
  end

  def contact_phone
    jid = from_me? ? payload[:chat_id] : payload[:from]
    normalized = jid.to_s.split('@').first.split(':').first
    return if normalized.blank? || jid.to_s.include?('@lid')

    normalized
  end

  def find_or_create_contact_inbox
    @contact_inbox = ContactInboxWithContactBuilder.new(
      source_id: contact_phone,
      inbox: inbox,
      contact_attributes: {
        name: contact_name,
        phone_number: "+#{contact_phone}"
      }
    ).perform
  end

  # No eco (is_from_me), sender_display_name/from_name descrevem quem enviou a mensagem pelo
  # WhatsApp da própria conta — ou seja, o nome da academia/hotel, não do cliente. Confirmado em
  # payload real do GOWA: um evento de eco não traz nenhum campo com o nome do CHAT (o cliente),
  # só do remetente (a própria conta). Isso corrompe a base quando a conta INICIA a conversa pelo
  # celular (lembrete, campanha) — o primeiro evento daquele contato já é um eco, e ele nasceria
  # com o nome da própria academia. Por isso cai pro telefone: um contato "556198..." que a
  # equipe renomeia depois é preferível a toda a base nascer com o nome da própria conta.
  def contact_name
    return contact_phone if from_me?

    payload[:sender_display_name].presence || payload[:from_name].presence || contact_phone
  end

  def find_or_create_conversation(contact_inbox)
    return inbox.conversations.where(contact_id: contact_inbox.contact_id).last if inbox.lock_to_single_conversation

    contact_inbox.conversations.where.not(status: :resolved).last ||
      Conversation.create!(contact: contact_inbox.contact, contact_inbox: contact_inbox, inbox: inbox, account: inbox.account, status: :open)
  end

  def merge_outgoing_echo(conversation)
    candidate = conversation.messages.where(message_type: :outgoing, source_id: nil).where('created_at > ?', 5.minutes.ago)
                            .find { |message| message.content.to_s.strip == payload[:body].to_s.strip }
    candidate&.update!(source_id: source_id)
  end

  def message_attributes
    {
      content: payload[:body],
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: from_me? ? :outgoing : :incoming,
      sender: from_me? ? nil : @contact_inbox.contact,
      source_id: source_id,
      created_at: parsed_timestamp
    }
  end

  def parsed_timestamp
    Time.zone.parse(payload[:timestamp].to_s)
  rescue ArgumentError
    Time.current
  end

  def attach_media(message)
    key, path = downloadable_media
    return if key.blank? || path.blank?

    downloaded = gowa_client.download_media(path)
    extension = File.extname(path.to_s).presence || extension_for(key)
    message.attachments.new(
      account_id: message.account_id,
      file_type: key,
      file: {
        io: StringIO.new(downloaded[:body]),
        filename: "gowa_#{external_id}#{extension}",
        content_type: downloaded[:content_type].presence || content_type_for(key)
      }
    )
  rescue Gowa::Client::Error, URI::InvalidURIError => e
    Rails.logger.warn "GOWA: mídia da mensagem #{external_id} ignorada: #{e.message}"
  end

  def downloadable_media
    key, media = media_payload
    return [nil, nil] if key.blank? || media.blank?

    path = media.is_a?(Hash) ? media['path'] || media[:path] : media
    return [nil, nil] if path.blank? || URI.parse(path).absolute?

    [key, path]
  end

  def media_payload
    %w[image audio video document].each do |key|
      return [key, payload[key]] if payload[key].present?
    end
    [nil, nil]
  end

  def gowa_client
    @gowa_client ||= Gowa::Client.new(
      inbox.channel.provider_config['gowa_base_url'],
      inbox.channel.gowa_username,
      inbox.channel.gowa_password
    )
  end

  def extension_for(key)
    { 'image' => '.jpeg', 'audio' => '.ogg', 'video' => '.mp4', 'document' => '' }.fetch(key)
  end

  def content_type_for(key)
    { 'image' => 'image/jpeg', 'audio' => 'audio/ogg', 'video' => 'video/mp4', 'document' => 'application/octet-stream' }.fetch(key)
  end
end
