class Whatsapp::DecryptionService
  require 'openssl'
  require 'base64'
  require 'net/http'

  # HKDF Info strings for different media types (WhatsApp protocol)
  INFO_STRINGS = {
    image: 'WhatsApp Image Keys',
    video: 'WhatsApp Video Keys',
    audio: 'WhatsApp Audio Keys',
    document: 'WhatsApp Document Keys',
    sticker: 'WhatsApp Image Keys'
  }.freeze

  def initialize(media_url, media_key, media_type)
    @media_url = media_url
    @media_key = Base64.decode64(media_key)
    @media_type = media_type.to_sym
    @info = INFO_STRINGS[@media_type] || INFO_STRINGS[:document]
  end

  def decrypt
    return nil unless @media_url && @media_key

    # 1. Download encrypted bytes
    encrypted_bytes = download_content
    return nil unless encrypted_bytes && encrypted_bytes.bytesize > 10

    Rails.logger.info "WuzAPI Decrypt: Downloaded #{encrypted_bytes.bytesize} bytes"

    # 2. Derive keys using HKDF SHA-256 (112 bytes total)
    expanded_key = OpenSSL::KDF.hkdf(
      @media_key,
      salt: ''.b,  # Empty binary string
      info: @info,
      length: 112,
      hash: 'sha256'
    )

    # 3. Split derived key
    iv = expanded_key[0...16]
    cipher_key = expanded_key[16...48]
    # mac_key = expanded_key[48...80]  # For verification (optional)
    # ref_key = expanded_key[80...112] # Not used

    # 4. WhatsApp file structure: [Encrypted Content] + [MAC (10 bytes)]
    # Remove the last 10 bytes (MAC)
    cipher_text = encrypted_bytes[0...-10]

    # 5. Try AES-256-CBC first (older WhatsApp versions)
    decrypted = try_aes_cbc(cipher_key, iv, cipher_text)

    # 6. If CBC fails, try CTR mode (some implementations use this)
    decrypted ||= try_aes_ctr(cipher_key, iv, cipher_text)

    return nil unless decrypted

    # 7. Validate that we got a valid image (check magic bytes)
    if valid_media?(decrypted)
      Rails.logger.info 'WuzAPI Decrypt: SUCCESS - Valid media detected'
      StringIO.new(decrypted)
    else
      Rails.logger.warn 'WuzAPI Decrypt: Decrypted but invalid media format'
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

    decipher.update!(data) + decipher.final

  rescue OpenSSL::Cipher::CipherError => e
    Rails.logger.debug { "AES-CBC failed: #{e.message}" }
    nil
  end

  def try_aes_ctr(key, iv, data)
    decipher = OpenSSL::Cipher.new('AES-256-CTR')
    decipher.decrypt
    decipher.key = key
    decipher.iv = iv

    decipher.update!(data) + decipher.final

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

  def download_content
    uri = URI.parse(@media_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.open_timeout = 10
    http.read_timeout = 30

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    response.is_a?(Net::HTTPSuccess) ? response.body.b : nil
  rescue StandardError => e
    Rails.logger.error "WuzAPI Decrypt Download Error: #{e.message}"
    nil
  end
end
