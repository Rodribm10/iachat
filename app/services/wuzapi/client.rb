require 'net/http'
require 'json'

class Wuzapi::Client # rubocop:disable Metrics/ClassLength
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
    upsert_webhook(user_token, webhook_url, :post)
  end

  def update_webhook(user_token, webhook_url)
    upsert_webhook(user_token, webhook_url, :put)
  end

  def get_webhook(user_token)
    request(
      :get,
      '/webhook',
      nil,
      user_auth_headers(user_token),
      fallback_paths: ['/webhook/get'],
      allow_base_fallback: true
    )
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
    candidates = build_request_candidates(path, fallback_paths, allow_base_fallback)
    errors = []

    candidates.each_with_index do |candidate, index|
      return perform_candidate_request(method, payload, headers, candidate, index.zero?)
    rescue Error => e
      raise unless retryable_not_found?(e)

      errors << e
      log_fallback_warning('endpoint not found', candidate, e.message)
    rescue ConnectionError => e
      errors << e
      log_fallback_warning('connection error', candidate, e.message)
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

    request_obj = build_http_request_object(method, uri.request_uri, payload, headers)

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

  def upsert_webhook(user_token, webhook_url, preferred_method)
    successful_request_without_verification = false
    last_error = nil

    webhook_attempts(preferred_method, webhook_url).each do |attempt|
      verification = request_and_verify_webhook(user_token, webhook_url, attempt)
      return verification if webhook_matches?(verification, webhook_url)

      successful_request_without_verification = true if verification.blank?
    rescue Error, ConnectionError => e
      last_error = e
    end

    return { 'success' => true, 'webhook' => webhook_url } if successful_request_without_verification

    raise(last_error || Error.new('Unable to configure webhook on Wuzapi'))
  end

  def webhook_payload_candidates(webhook_url)
    [
      { 'webhook' => webhook_url, 'events' => ['All'] },
      { 'webhook' => webhook_url, 'events' => %w[Message ReadReceipt Presence ChatPresence HistorySync] },
      { 'WebhookURL' => webhook_url, 'Events' => ['All'] },
      { 'WebhookURL' => webhook_url, 'Events' => %w[Message ReadReceipt Presence ChatPresence HistorySync] }
    ]
  end

  def safe_get_webhook(user_token)
    get_webhook(user_token)
  rescue Error, ConnectionError
    nil
  end

  def webhook_matches?(payload, expected_url)
    return false if payload.blank?

    actual = extract_webhook_url(payload)
    return false if actual.blank?

    normalize_webhook_url(actual) == normalize_webhook_url(expected_url)
  end

  def extract_webhook_url(payload)
    payload['webhook'] ||
      payload['WebhookURL'] ||
      payload['url'] ||
      payload.dig('data', 'webhook') ||
      payload.dig('data', 'WebhookURL') ||
      payload.dig('data', 'url')
  end

  def normalize_webhook_url(url)
    url.to_s.strip.delete_suffix('/')
  end

  def handle_response(response)
    Rails.logger.info "WUZAPI RAW RESPONSE: status=#{response.code} ct=#{response['content-type']} body=#{response.body.to_s.truncate(1000)}"

    return parse_success_response(response) if success_status?(response)
    return raise_authentication_error(response) if auth_error_status?(response)

    raise Error, "API Error: #{response.code} #{response.body}"
  end

  def build_request_candidates(path, fallback_paths, allow_base_fallback)
    candidate_paths = [path, *Array(fallback_paths)].map { |p| normalize_path(p) }.uniq
    candidate_bases = [base_url]
    if allow_base_fallback
      alternative = alternate_base_url(base_url)
      candidate_bases << alternative if alternative.present? && alternative != base_url
    end

    candidate_bases.product(candidate_paths).map do |candidate_base, candidate_path|
      { base: candidate_base, path: candidate_path }
    end
  end

  def perform_candidate_request(method, payload, headers, candidate, is_primary)
    response = execute_http_request(method, candidate[:base], candidate[:path], payload, headers)
    log_successful_fallback(candidate) unless is_primary
    handle_response(response)
  end

  def log_successful_fallback(candidate)
    Rails.logger.info("Wuzapi fallback route worked base=#{candidate[:base]} path=#{candidate[:path]}")
  end

  def log_fallback_warning(reason, candidate, details)
    Rails.logger.warn("Wuzapi #{reason}, trying fallback route base=#{candidate[:base]} path=#{candidate[:path]} #{details}")
  end

  def build_http_request_object(method, request_uri, payload, headers)
    request_obj = http_request_class_for(method).new(request_uri)
    request_obj['Content-Type'] = 'application/json'
    request_obj['Accept'] = 'application/json'
    headers.each { |k, v| request_obj[k] = v }
    request_obj.body = payload.to_json if payload
    request_obj
  end

  def http_request_class_for(method)
    {
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      put: Net::HTTP::Put,
      delete: Net::HTTP::Delete
    }.fetch(method)
  end

  def parse_response_json(raw_body)
    JSON.parse(raw_body)
  rescue JSON::ParserError
    Rails.logger.warn "Wuzapi response parse error or non-JSON: #{raw_body}"
    { 'raw_body' => raw_body }
  end

  def extract_qr_code(body)
    nested = extract_nested_qr_code(body)
    return nested if nested.present?

    body['qr'] || body['QRCode'] || body['QR'] || body['base64'] || body['image']
  end

  def extract_nested_qr_code(body)
    return nil if body['data'].blank?

    return extract_qr_code_from_hash(body['data']) if body['data'].is_a?(Hash)
    return body['data'] if body['data'].is_a?(String) && possible_qr_blob?(body['data'])

    nil
  end

  def extract_qr_code_from_hash(data)
    data['qrcode'] || data['qr'] || data['QRCode'] || data['QR'] || data['base64'] || data['image']
  end

  def possible_qr_blob?(value)
    value.start_with?('data:') || value.length > 50
  end

  def webhook_attempts(preferred_method, webhook_url)
    methods = [preferred_method, :put, :post].uniq
    payloads = webhook_payload_candidates(webhook_url)
    methods.product(payloads).map { |method, payload| { method: method, payload: payload } }
  end

  def request_and_verify_webhook(user_token, _webhook_url, attempt)
    request(
      attempt[:method],
      '/webhook',
      attempt[:payload],
      user_auth_headers(user_token),
      fallback_paths: ['/webhook/set'],
      allow_base_fallback: true
    )
    safe_get_webhook(user_token)
  end

  def success_status?(response)
    code = response.code.to_i
    code >= 200 && code < 300
  end

  def auth_error_status?(response)
    [401, 403].include?(response.code.to_i)
  end

  def parse_success_response(response)
    content_type = response['content-type'] || ''
    return image_success_response(response.body, content_type) if content_type.include?('image/')

    body = parse_response_json(response.body)
    body['qrcode'] ||= extract_qr_code(body)
    body
  end

  def image_success_response(raw_body, content_type)
    require 'base64'
    base64_image = Base64.strict_encode64(raw_body)
    { 'qrcode' => "data:#{content_type};base64,#{base64_image}" }
  end

  def raise_authentication_error(response)
    raise AuthenticationError, "Authentication failed: #{response.code} #{response.body}"
  end
end
