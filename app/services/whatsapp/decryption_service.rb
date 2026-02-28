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
    return nil unless @media_key && encrypted_bytes && encrypted_bytes.bytesize > 10

    Rails.logger.info "WuzAPI Decrypt: Processing #{encrypted_bytes.bytesize} bytes"

    # Derive keys using HKDF SHA-256 (112 bytes total)
    expanded_key = OpenSSL::KDF.hkdf(
      @media_key,
      salt: ''.b,
      info: @info,
      length: 112,
      hash: 'sha256'
    )

    iv = expanded_key[0...16]
    cipher_key = expanded_key[16...48]

    # WhatsApp file structure: [Encrypted Content] + [MAC (10 bytes)]
    cipher_text = encrypted_bytes[0...-10]

    decrypted = try_aes_cbc(cipher_key, iv, cipher_text)
    decrypted ||= try_aes_ctr(cipher_key, iv, cipher_text)

    return nil unless decrypted

    if valid_media?(decrypted)
      Rails.logger.info 'WuzAPI Decrypt: SUCCESS - Valid media detected'
      StringIO.new(decrypted)
    else
      Rails.logger.warn "WuzAPI Decrypt: Decrypted but invalid format (first bytes: #{decrypted.bytes[0..3].map { |b| format('%02X', b) }.join(' ')})"
      nil
    end
  rescue StandardError => e
    Rails.logger.error "WuzAPI Decrypt Error: #{e.class} - #{e.message}"
    nil
  end

  private

  def try_aes_cbc(key, iv, data)
    decipher = OpenSSL::Cipher.new('AES-256-CBC')
    decipher.decrypt
    decipher.key = key
    decipher.iv = iv
    decipher.padding = 0  # WhatsApp doesn't use PKCS7 padding

    decipher.update(data) + decipher.final

  rescue OpenSSL::Cipher::CipherError => e
    Rails.logger.debug { "AES-CBC failed: #{e.message}" }
    nil
  end

  def try_aes_ctr(key, iv, data)
    decipher = OpenSSL::Cipher.new('AES-256-CTR')
    decipher.decrypt
    decipher.key = key
    decipher.iv = iv

    decipher.update(data) + decipher.final

  rescue OpenSSL::Cipher::CipherError => e
    Rails.logger.debug { "AES-CTR failed: #{e.message}" }
    nil
  end

  def valid_media?(data)
    return false if data.nil? || data.bytesize < 4

    bytes = data.bytes[0..7]

    # JPEG: FF D8 FF
    return true if bytes[0..2] == [0xFF, 0xD8, 0xFF]

    # PNG: 89 50 4E 47
    return true if bytes[0..3] == [0x89, 0x50, 0x4E, 0x47]

    # WebP: RIFF....WEBP
    return true if data[0..3] == 'RIFF' && data[8..11] == 'WEBP'

    # MP4/MOV: ftyp
    return true if data[4..7] == 'ftyp'

    # MP3: ID3 or FF FB/FF FA
    return true if data[0..2] == 'ID3' || bytes[0..1] == [0xFF, 0xFB] || bytes[0..1] == [0xFF, 0xFA]

    # OGG: OggS
    return true if data[0..3] == 'OggS'

    # PDF: %PDF
    return true if data[0..3] == '%PDF'

    false
  end

end
