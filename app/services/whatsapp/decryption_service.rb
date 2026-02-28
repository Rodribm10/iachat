class Whatsapp::DecryptionService
  require 'openssl'
  require 'base64'

  # HKDF Info strings for different media types (WhatsApp protocol)
  INFO_STRINGS = {
    image: 'WhatsApp Image Keys',
    video: 'WhatsApp Video Keys',
    audio: 'WhatsApp Audio Keys',
    document: 'WhatsApp Document Keys',
    sticker: 'WhatsApp Image Keys'
  }.freeze

  def initialize(media_key, media_type)
    @media_key = Base64.decode64(media_key)
    @media_type = media_type.to_sym
    @info = INFO_STRINGS[@media_type] || INFO_STRINGS[:document]
  end

  def decrypt_bytes(encrypted_bytes)
    return nil unless valid_input?(encrypted_bytes)

    expanded_key = derive_keys
    iv = expanded_key[0...16]
    cipher_key = expanded_key[16...48]
    cipher_text = encrypted_bytes[0...-10]

    decrypted = try_aes_cbc(cipher_key, iv, cipher_text) || try_aes_ctr(cipher_key, iv, cipher_text)
    validate_decrypted_media(decrypted)
  rescue StandardError => e
    Rails.logger.error "WuzAPI Decrypt Error: #{e.class} - #{e.message}"
    nil
  end

  private

  def valid_input?(bytes)
    @media_key && bytes && bytes.bytesize > 10
  end

  def derive_keys
    OpenSSL::KDF.hkdf(
      @media_key,
      salt: ''.b,
      info: @info,
      length: 112,
      hash: 'sha256'
    )
  end

  def validate_decrypted_media(decrypted)
    return nil unless decrypted

    if valid_media?(decrypted)
      Rails.logger.info 'WuzAPI Decrypt: SUCCESS - Valid media detected'
      StringIO.new(decrypted)
    else
      log_invalid_media(decrypted)
      nil
    end
  end

  def log_invalid_media(decrypted)
    first_bytes = decrypted.bytes[0..3].map { |b| format('%02X', b) }.join(' ')
    Rails.logger.warn "WuzAPI Decrypt: Decrypted but invalid format (first bytes: #{first_bytes})"
  end

  def try_aes_cbc(key, iv, data)
    decipher = OpenSSL::Cipher.new('AES-256-CBC')
    decipher.decrypt
    decipher.key = key
    decipher.iv = iv
    decipher.padding = 0  # WhatsApp doesn't use PKCS7 padding

    # rubocop:disable Rails/SaveBang
    decipher.update(data) + decipher.final
    # rubocop:enable Rails/SaveBang

  rescue OpenSSL::Cipher::CipherError => e
    Rails.logger.debug { "AES-CBC failed: #{e.message}" }
    nil
  end

  def try_aes_ctr(key, iv, data)
    decipher = OpenSSL::Cipher.new('AES-256-CTR')
    decipher.decrypt
    decipher.key = key
    decipher.iv = iv

    # rubocop:disable Rails/SaveBang
    decipher.update(data) + decipher.final
    # rubocop:enable Rails/SaveBang

  rescue OpenSSL::Cipher::CipherError => e
    Rails.logger.debug { "AES-CTR failed: #{e.message}" }
    nil
  end

  def valid_media?(data)
    return false if data.nil? || data.bytesize < 4

    bytes = data.bytes[0..7]

    # Quick header checks for common WhatsApp media types
    return true if bytes[0..2] == [0xFF, 0xD8, 0xFF] # JPEG
    return true if bytes[0..3] == [0x89, 0x50, 0x4E, 0x47] # PNG
    return true if webp?(data)
    return true if mp4?(data)
    return true if audio?(data, bytes)
    return true if data[0..3] == 'OggS' || data[0..3] == '%PDF'

    false
  end

  def webp?(data)
    data[0..3] == 'RIFF' && data[8..11] == 'WEBP'
  end

  def mp4?(data)
    data[4..7] == 'ftyp'
  end

  def audio?(data, bytes)
    data[0..2] == 'ID3' || [0xFF, 0xFB].include?(bytes[0..1]) || [0xFF, 0xFA].include?(bytes[0..1])
  end
end
