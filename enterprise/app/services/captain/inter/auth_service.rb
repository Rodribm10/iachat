require 'faraday'

# Obtém um token OAuth da API do Banco Inter usando mTLS.
# O token é cacheado no Redis pelo tempo de expiração menos 5 minutos de margem.
class Captain::Inter::AuthService
  API_BASE_URL = 'https://cdpj.partners.bancointer.com.br'.freeze
  TOKEN_URL = '/oauth/v2/token'.freeze

  def initialize(unit)
    @unit = unit
  end

  def token
    cached_token = Redis::Alfred.get(cache_key)
    return cached_token if cached_token.present?

    fetch_new_token
  end

  private

  def cache_key
    "inter_token:unit_#{@unit.id}"
  end

  def fetch_new_token
    raise "Unit #{@unit.name} is inactive" unless @unit.active?

    response = connection.post(TOKEN_URL) do |req|
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.headers['Authorization'] = "Basic #{Base64.strict_encode64("#{@unit.inter_client_id}:#{@unit.inter_client_secret}")}"
      req.body = URI.encode_www_form({
                                       grant_type: 'client_credentials',
                                       scope: 'cob.write cob.read pix.write pix.read webhook.read webhook.write'
                                     })
    end

    raise "Auth Failed: #{response.body}" unless response.success?

    data = JSON.parse(response.body)
    access_token = data['access_token']
    expires_in = data['expires_in'].to_i

    # Cacheia com margem de 5 minutos antes do vencimento
    Redis::Alfred.setex(cache_key, access_token, expires_in - 300)

    access_token
  end

  def connection
    @connection ||= Faraday.new(url: API_BASE_URL) do |conn|
      cert_raw = @unit.inter_cert_content.presence || File.read(@unit.resolved_inter_cert_path)
      key_raw  = @unit.inter_key_content.presence  || File.read(@unit.resolved_inter_key_path)

      conn.ssl[:client_cert] = OpenSSL::X509::Certificate.new(cert_raw)
      conn.ssl[:client_key]  = OpenSSL::PKey::RSA.new(key_raw)
      conn.adapter Faraday.default_adapter
    end
  end
end
