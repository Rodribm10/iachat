require 'net/http'
require 'json'
require 'erb'

class Gowa::Client # rubocop:disable Metrics/ClassLength
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class ConnectionError < Error; end

  def initialize(base_url, username, password)
    @base_url = normalize_url(base_url)
    @username = username
    @password = password
    validate_base_url!
  end

  def create_device(device_id)
    request(:post, '/devices', { device_id: device_id })
  end

  def delete_device(device_id)
    request(:delete, "/devices/#{escape(device_id)}")
  end

  def device_status(device_id)
    request(:get, "/devices/#{escape(device_id)}/status")
  end

  def start_login(device_id)
    request(:get, "/devices/#{escape(device_id)}/login")
  end

  def logout(device_id)
    request(:post, "/devices/#{escape(device_id)}/logout")
  end

  def update_webhook(device_id, webhook_url, webhook_secret)
    request(
      :patch,
      "/devices/#{escape(device_id)}/webhook",
      {
        webhook_url: webhook_url,
        webhook_secret: webhook_secret,
        webhook_events: 'message'
      }
    )
  end

  # GOWA expoe a reacao como acao sobre a mensagem alvo, nao como um envio novo:
  # POST /message/{id}/reaction  { phone, emoji }. Emoji vazio remove a reacao.
  def send_reaction(device_id, phone_number, message_id, emoji)
    request(
      :post,
      "/message/#{escape(message_id)}/reaction",
      { phone: normalized_jid(phone_number), emoji: emoji.to_s },
      device_id: device_id
    )
  end

  def send_text(device_id, phone_number, message, reply_message_id: nil)
    request(
      :post,
      '/send/message',
      { phone: normalized_jid(phone_number), message: message, reply_message_id: reply_message_id }.compact,
      device_id: device_id
    )
  end

  def send_attachment(device_id, phone_number, attachment, caption: nil, reply_message_id: nil)
    endpoint, field_name = attachment_endpoint(attachment.file.content_type)
    payload = {
      :phone => normalized_jid(phone_number),
      :caption => caption,
      :reply_message_id => reply_message_id,
      field_name => {
        filename: attachment.file.filename.to_s,
        content_type: attachment.file.content_type,
        content: attachment_content(attachment)
      }
    }.compact
    multipart_request(:post, endpoint, payload, device_id: device_id)
  end

  def send_presence(device_id, phone_number, status)
    request(
      :post,
      '/send/chat-presence',
      { phone: normalized_jid(phone_number), state: status },
      device_id: device_id
    )
  end

  def download_media(path)
    uri = media_uri(path)
    request_object = Net::HTTP::Get.new(uri.request_uri)
    apply_headers(request_object, nil)
    response = perform_http_request(request_object, uri)
    raise_for_response(response)

    { body: response.body, content_type: response['content-type'] }
  end

  private

  def normalize_url(url)
    url.to_s.sub(%r{/$}, '')
  end

  def validate_base_url!
    uri = URI.parse(@base_url)
    return if uri.is_a?(URI::HTTP) && uri.userinfo.blank? && uri.host.present?

    raise ArgumentError, 'A URL do GOWA deve usar HTTP(S) e não pode conter credenciais.'
  rescue URI::InvalidURIError
    raise ArgumentError, 'A URL do GOWA é inválida.'
  end

  def request(method, path, payload = nil, device_id: nil)
    uri = URI.parse("#{@base_url}#{path}")
    request_object = request_object_for(method, uri)
    apply_headers(request_object, device_id)
    request_object.body = payload.to_json if payload
    request_object['Content-Type'] = 'application/json' if payload

    response = perform_http_request(request_object, uri)
    parse_response(response)
  end

  def multipart_request(method, path, payload, device_id:)
    uri = URI.parse("#{@base_url}#{path}")
    boundary = "----ChatwootGowa#{SecureRandom.hex(12)}"
    request_object = request_object_for(method, uri)
    apply_headers(request_object, device_id)
    request_object['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    request_object.body = multipart_body(payload, boundary)

    parse_response(perform_http_request(request_object, uri))
  end

  def request_object_for(method, uri)
    {
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      patch: Net::HTTP::Patch,
      delete: Net::HTTP::Delete
    }.fetch(method).new(uri.request_uri)
  end

  def apply_headers(request_object, device_id)
    request_object['Accept'] = 'application/json'
    request_object['X-Device-Id'] = device_id if device_id.present?
    request_object.basic_auth(@username, @password)
  end

  def multipart_body(payload, boundary)
    parts = payload.map do |name, value|
      if value.is_a?(Hash) && value.key?(:content)
        [
          "--#{boundary}",
          %(Content-Disposition: form-data; name="#{name}"; filename="#{value[:filename]}"),
          "Content-Type: #{value[:content_type]}",
          '',
          value[:content]
        ].join("\r\n")
      else
        ["--#{boundary}", %(Content-Disposition: form-data; name="#{name}"), '', value.to_s].join("\r\n")
      end
    end
    "#{parts.join("\r\n")}\r\n--#{boundary}--\r\n"
  end

  def perform_http_request(request_object, uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 30
    http.request(request_object)
  rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
    raise ConnectionError, "Não foi possível conectar ao GOWA: #{e.message}"
  end

  def parse_response(response)
    raise_for_response(response)
    JSON.parse(response.body)
  rescue JSON::ParserError
    { 'raw_body' => response.body }
  end

  def raise_for_response(response)
    return if response.code.to_i.between?(200, 299)

    message = "Erro do GOWA: #{response.code} #{response.body.to_s.truncate(500)}"
    raise AuthenticationError, message if response.code.to_i.in?([401, 403])

    raise Error, message
  end

  def media_uri(path)
    uri = URI.parse(path)
    uri = URI.join("#{@base_url}/", path) if uri.relative?
    base_uri = URI.parse(@base_url)
    return uri if uri.host == base_uri.host && uri.port == base_uri.port

    raise Error, 'O GOWA devolveu uma mídia fora do servidor configurado.'
  rescue URI::InvalidURIError
    raise Error, 'O caminho de mídia devolvido pelo GOWA é inválido.'
  end

  def attachment_endpoint(content_type)
    return ['/send/image', :image] if content_type.start_with?('image/')
    return ['/send/audio', :audio] if content_type.start_with?('audio/')
    return ['/send/video', :video] if content_type.start_with?('video/')

    ['/send/file', :file]
  end

  def attachment_content(attachment)
    attachment.file.blob.open do |file|
      file.binmode
      file.read
    end
  end

  def normalized_jid(phone_number)
    raw_phone = phone_number.to_s
    return raw_phone if raw_phone.include?('@')

    "#{raw_phone.gsub(/\D/, '')}@s.whatsapp.net"
  end

  def escape(value)
    ERB::Util.url_encode(value.to_s)
  end
end
