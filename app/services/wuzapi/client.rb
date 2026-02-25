require 'net/http'
require 'json'

class Wuzapi::Client
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class ConnectionError < Error; end

  attr_reader :base_url

  def initialize(base_url)
    @base_url = normalize_url(base_url)
  end

  # Admin Endpoints (Use Authorization header)
  def create_user(admin_token, name, user_token)
    payload = { name: name, token: user_token }
    request(:post, '/admin/users', payload, admin_auth_headers(admin_token))
  end

  def delete_user(admin_token, user_id)
    request(:delete, "/admin/users/#{user_id}", nil, admin_auth_headers(admin_token))
  end

  # User Endpoints (Use token header)
  def send_text(user_token, phone_number, body, **options)
    # Payload MUST be Case-Sensitive: Key 'Phone' and 'Body'
    payload = { 'Phone' => phone_number, 'Body' => body }.merge(options)
    request(
      :post,
      '/chat/send/text',
      payload,
      user_auth_headers(user_token),
      fallback_paths: ['/send/text'],
      allow_base_fallback: true
    )
  end

  def send_image(user_token, phone_number, base64_data, caption = nil)
    # Some Wuzapi builds expect `Image` while older forks accepted `Body`.
    # Send both for compatibility; `Image` is the official key in current docs.
    payload = {
      'Phone' => phone_number,
      'Image' => base64_data,
      'Body' => base64_data,
      'Caption' => caption
    }
    request(
      :post,
      '/chat/send/image',
      payload,
      user_auth_headers(user_token),
      fallback_paths: ['/send/image'],
      allow_base_fallback: true
    )
  end

  def send_file(user_token, phone_number, base64_data, filename)
    payload = { 'Phone' => phone_number, 'Body' => base64_data, 'Filename' => filename }
    request(
      :post,
      '/chat/send/file',
      payload,
      user_auth_headers(user_token),
      fallback_paths: ['/send/file'],
      allow_base_fallback: true
    )
  end

  def send_reaction(user_token, phone_number, message_id, emoji)
    payload = { 'Phone' => phone_number, 'Body' => emoji, 'Id' => message_id }
    request(
      :post,
      '/chat/react',
      payload,
      user_auth_headers(user_token),
      fallback_paths: ['/send/react'],
      allow_base_fallback: true
    )
  end

  def send_chat_presence(user_token, phone_number, state, media = nil)
    # State: "composing" or "paused"
    # Media: "audio" (optional)
    payload = { 'Phone' => phone_number, 'State' => state }
    payload['Media'] = media if media
    request(
      :post,
      '/chat/presence',
      payload,
      user_auth_headers(user_token),
      fallback_paths: ['/send/presence'],
      allow_base_fallback: true
    )
  end

  def download_media(user_token, media_url)
    # Some WuzAPI versions use a dedicated download endpoint to proxy Meta CDN
    payload = { 'URL' => media_url }
    request(
      :post,
      '/chat/downloadimage',
      payload,
      user_auth_headers(user_token),
      fallback_paths: ['/downloadimage'],
      allow_base_fallback: true
    )
  end

  def session_status(user_token)
    request(:get, '/session/status', nil, user_auth_headers(user_token))
  end

  def get_qr_code(user_token)
    request(:get, '/session/qr', nil, user_auth_headers(user_token))
  end

  def session_connect(user_token)
    request(:post, '/session/connect', {}, user_auth_headers(user_token))
  end

  def session_disconnect(user_token)
    request(:post, '/session/disconnect', nil, user_auth_headers(user_token))
  end

  def session_logout(user_token)
    request(:get, '/session/logout', nil, user_auth_headers(user_token))
  end

  def set_webhook(user_token, webhook_url)
    # Wuzapi expects PascalCase keys 'WebhookURL' and 'Events' with 'All' per user verification.
    payload = { 'WebhookURL' => webhook_url, 'Events' => ['All'] }
    request(:post, '/webhook', payload, user_auth_headers(user_token))
  end

  def update_webhook(user_token, webhook_url)
    payload = { 'WebhookURL' => webhook_url, 'Events' => ['All'] }
    request(:put, '/webhook', payload, user_auth_headers(user_token))
  end

  def get_webhook(user_token)
    request(:get, '/webhook', nil, user_auth_headers(user_token))
  end

  private

  def normalize_url(url)
    url.to_s.gsub(%r{/$}, '')
  end

  def admin_auth_headers(token)
    { 'Authorization' => token }
  end

  def user_auth_headers(token)
    { 'token' => token }
  end

  def request(method, path, payload, headers, fallback_paths: [], allow_base_fallback: false)
    candidate_paths = [path, *Array(fallback_paths)].map { |p| normalize_path(p) }.uniq
    candidate_bases = [base_url]
    primary_path = candidate_paths.first
    primary_base = candidate_bases.first

    if allow_base_fallback
      alternative = alternate_base_url(base_url)
      candidate_bases << alternative if alternative.present? && alternative != base_url
    end

    errors = []

    candidate_bases.each do |candidate_base|
      candidate_paths.each do |candidate_path|
        response = execute_http_request(method, candidate_base, candidate_path, payload, headers)
        if candidate_base != primary_base || candidate_path != primary_path
          Rails.logger.info("Wuzapi fallback route worked base=#{candidate_base} path=#{candidate_path}")
        end
        return handle_response(response)
      rescue Error => e
        if retryable_not_found?(e)
          errors << e
          Rails.logger.warn("Wuzapi endpoint not found, trying fallback route base=#{candidate_base} path=#{candidate_path}")
          next
        end

        raise
      rescue ConnectionError => e
        errors << e
        Rails.logger.warn("Wuzapi connection error on fallback route base=#{candidate_base} path=#{candidate_path}: #{e.message}")
        next
      end
    end

    raise(errors.last || Error.new('Wuzapi request failed with unknown error'))
  end

  def execute_http_request(method, target_base_url, path, payload, headers)
    uri = URI.parse("#{target_base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)

    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    request_obj = case method
                  when :get
                    Net::HTTP::Get.new(uri.request_uri)
                  when :post
                    Net::HTTP::Post.new(uri.request_uri)
                  when :put
                    Net::HTTP::Put.new(uri.request_uri)
                  when :delete
                    Net::HTTP::Delete.new(uri.request_uri)
                  end

    request_obj['Content-Type'] = 'application/json'
    request_obj['Accept'] = 'application/json'
    headers.each { |k, v| request_obj[k] = v }
    request_obj.body = payload.to_json if payload

    begin
      http.request(request_obj)
    rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout, Net::ReadTimeout => e
      raise ConnectionError, "Could not connect to Wuzapi: #{e.message}"
    end
  end

  def normalize_path(path)
    return '/' if path.blank?

    path.start_with?('/') ? path : "/#{path}"
  end

  def alternate_base_url(url)
    normalized = normalize_url(url)
    if normalized.match?(%r{/api/?$})
      normalized.gsub(%r{/api/?$}, '')
    else
      "#{normalized}/api"
    end
  end

  def retryable_not_found?(error)
    error.message.include?('API Error: 404')
  end

  def handle_response(response)
    Rails.logger.info "WUZAPI RAW RESPONSE: status=#{response.code} ct=#{response['content-type']} body=#{response.body.to_s.truncate(1000)}"

    if response.code.to_i >= 200 && response.code.to_i < 300
      content_type = response['content-type'] || ''

      if content_type.include?('image/')
        require 'base64'
        base64_image = Base64.strict_encode64(response.body)
        return { 'qrcode' => "data:#{content_type};base64,#{base64_image}" }
      end

      begin
        body = JSON.parse(response.body)
        # Normalize keys to 'qrcode'
        # Check nested data object
        if body['data'].is_a?(Hash)
          found = body['data']['qrcode'] || body['data']['qr'] || body['data']['QRCode'] || body['data']['QR'] || body['data']['base64'] || body['data']['image']
          body['qrcode'] = found if found
        # Check if data is the string itself
        elsif body['data'].is_a?(String) && (body['data'].start_with?('data:') || body['data'].length > 50)
          body['qrcode'] = body['data']
        end

        # Check root keys if still not found
        body['qrcode'] = body['qr'] || body['QRCode'] || body['QR'] || body['base64'] || body['image'] unless body['qrcode']

        return body
      rescue JSON::ParserError
        Rails.logger.warn "Wuzapi response parse error or non-JSON: #{response.body}"
        return { 'raw_body' => response.body }
      end
    elsif response.code.to_i == 401 || response.code.to_i == 403
      raise AuthenticationError, "Authentication failed: #{response.code} #{response.body}"
    else
      raise Error, "API Error: #{response.code} #{response.body}"
    end
  end
end
