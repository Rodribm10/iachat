require 'net/http'
require 'json'

class EvolutionApi::Client
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class ConnectionError < Error; end

  attr_reader :base_url, :api_token

  def initialize(base_url, api_token)
    @base_url = normalize_url(base_url)
    @api_token = api_token
  end

  def check_api
    request(:get, '/instance/fetchInstances')
  end

  # Instance Endpoints
  def create_instance(instance_name)
    payload = { instanceName: instance_name, token: instance_name }
    request(:post, '/instance/create', payload)
  end

  def get_qr_code(instance_name)
    request(:get, "/instance/qr?instanceName=#{instance_name}")
  end

  def session_status(instance_name)
    request(:get, "/instance/connectionState?instanceName=#{instance_name}")
  rescue StandardError => _e
    # Log error or handle retry if needed
    {}
  end

  def logout_instance(instance_name)
    request(:delete, "/instance/logout?instanceName=#{instance_name}")
  end

  def delete_instance(instance_name)
    request(:delete, "/instance/delete?instanceName=#{instance_name}")
  end

  def set_instance_settings(instance_name, settings)
    # Evolution API uses /settings/set/instanceName
    # settings is a hash with alwaysOnline, rejectCall, etc.
    request(:post, "/settings/set?instanceName=#{instance_name}", settings)
  end

  def set_settings(instance_name, settings)
    # Duplicate p/ compatibilidade se necessário com rotas /instance/update
    request(:post, "/instance/update?instanceName=#{instance_name}", settings)
  end

  # Webhook
  def set_webhook(instance_name, webhook_url)
    payload = {
      webhook: {
        url: webhook_url,
        byEvents: false,
        base64: false,
        events: %w[
          MESSAGES_UPSERT
          MESSAGES_UPDATE
          SEND_MESSAGE
          CONNECTION_UPDATE
        ]
      }
    }
    request(:post, "/webhook/set?instanceName=#{instance_name}", payload)
  end

  # Sending messages
  def send_text(instance_name, phone_number, body, **options)
    payload = { number: phone_number, text: body }.merge(options)
    request(:post, "/send/text?instanceName=#{instance_name}", payload)
  end

  def send_image(instance_name, phone_number, base64_or_url, caption = nil)
    payload = { number: phone_number, mediaMessage: { mediatype: 'image', media: base64_or_url, caption: caption } }
    request(:post, "/send/media?instanceName=#{instance_name}", payload)
  end

  def send_file(instance_name, phone_number, base64_or_url, filename)
    payload = { number: phone_number, mediaMessage: { mediatype: 'document', media: base64_or_url, fileName: filename } }
    request(:post, "/send/media?instanceName=#{instance_name}", payload)
  end

  private

  def normalize_url(url)
    url.to_s.gsub(%r{/$}, '')
  end

  def auth_headers
    { 'apikey' => @api_token }
  end

  def request(method, path, payload = nil)
    uri = URI.parse("#{base_url}#{path}")
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

    auth_headers.each { |k, v| request_obj[k] = v }
    request_obj.body = payload.to_json if payload

    begin
      response = http.request(request_obj)
      handle_response(response)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
      raise ConnectionError, "Could not connect to Evolution Go: #{e.message}"
    end
  end

  def handle_response(response)
    Rails.logger.info "EVOLUTION RAW RESPONSE: status=#{response.code} body=#{response.body.to_s.truncate(1000)}"

    if response.code.to_i >= 200 && response.code.to_i < 300
      begin
        body = JSON.parse(response.body)
        # Tratamento pro QR Code (Evolution as vezes volta a string de base64 no body ou num campo)
        if body['qrcode'] || body['base64'] || body['qr'] || body['image']
          body['qrcode'] ||= body['base64'] || body['qr'] || body['image']
        elsif body.key?('instance') && body['instance']['qr']
          body['qrcode'] = body['instance']['qr']
        end
        return body
      rescue JSON::ParserError
        return { 'raw_body' => response.body }
      end
    elsif response.code.to_i == 401 || response.code.to_i == 403
      raise AuthenticationError, "Authentication failed: #{response.code} #{response.body}"
    else
      raise Error, "API Error: #{response.code} #{response.body}"
    end
  end
end
