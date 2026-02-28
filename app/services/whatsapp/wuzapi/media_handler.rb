class Whatsapp::Wuzapi::MediaHandler
  def initialize(inbox, parser)
    @inbox = inbox
    @parser = parser
  end

  def process(message, attachment_data)
    file_io = download_or_decrypt_media(attachment_data, @parser.message_type)
    return if file_io.blank?

    message.attachments.new(
      account_id: message.account_id,
      file_type: file_content_type(@parser.message_type),
      file: {
        io: file_io,
        filename: final_filename(attachment_data),
        content_type: sanitize_content_type(attachment_data[:mimetype], @parser.message_type)
      }
    )
  end

  private

  def download_or_decrypt_media(data, type)
    url = data[:external_url]
    decoded = download_via_wuzapi(url)
    return StringIO.new(decoded) if decoded

    encrypted_bytes = download_from_cdn(url)
    return nil if encrypted_bytes.blank?

    if data[:media_key].present?
      decrypted = decrypt_media(encrypted_bytes, data[:media_key], type)
      return decrypted if decrypted
    end

    StringIO.new(encrypted_bytes)
  rescue StandardError => e
    Rails.logger.error "WuzAPI: Media handling failed - #{e.message}"
    nil
  end

  def download_via_wuzapi(url)
    response = wuzapi_client.download_media(wuzapi_token, url)
    return nil unless response.is_a?(Hash) && response['data'].present?

    image_data = response['data'].sub(/^data:.*?;base64,/, '')
    decoded = Base64.decode64(image_data)
    decoded.bytesize > 1000 ? decoded : nil
  rescue StandardError => e
    Rails.logger.warn "WuzAPI: Endpoint download failed - #{e.message}"
    nil
  end

  def download_from_cdn(url)
    tempfile = Down.download(url, open_timeout: 10, read_timeout: 30, ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE)
    tempfile.read.b
  rescue StandardError => e
    Rails.logger.error "WuzAPI: CDN download failed - #{e.message}"
    nil
  end

  def decrypt_media(bytes, key, type)
    Whatsapp::DecryptionService.new(key, file_content_type(type)).decrypt_bytes(bytes)
  end

  def final_filename(data)
    name = data[:file_name] || "wuzapi_#{Time.now.to_i}"
    ext = File.extname(name)
    ext = detect_extension(data[:mimetype], @parser.message_type) if ext.blank?
    # Normalise audio extension: WhatsApp always sends OGG/Opus, never MP3
    ext = '.ogg' if @parser.message_type == :audio && ext == '.mp3'
    "#{File.basename(name, '.*')}#{ext}"
  end

  def sanitize_content_type(mimetype, type)
    # WhatsApp audio is OGG-wrapped Opus. audio/opus is raw Opus (wrong container header).
    # Saving as audio/ogg ensures browsers can play via <audio> without issues.
    return 'audio/ogg' if type == :audio && mimetype.to_s.include?('opus')

    mimetype || 'application/octet-stream'
  end

  def detect_extension(mimetype, type)
    return '.jpg' if type == :image || type == :sticker
    return '.ogg' if type == :audio
    return '.mp4' if type == :video

    case mimetype
    when 'image/png' then '.png'
    when 'image/webp' then '.webp'
    when 'image/gif' then '.gif'
    when 'audio/ogg' then '.ogg'
    when 'video/webm' then '.webm'
    else '.bin'
    end
  end

  def file_content_type(type)
    case type
    when :image, :sticker then :image
    when :audio then :audio
    when :video then :video
    else :file
    end
  end

  def wuzapi_client
    @wuzapi_client ||= ::Wuzapi::Client.new(@inbox.channel.provider_config['wuzapi_base_url'])
  end

  def wuzapi_token
    @inbox.channel.wuzapi_user_token
  end
end
