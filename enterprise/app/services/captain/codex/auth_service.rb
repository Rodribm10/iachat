require 'faraday'

# Gerencia credenciais OAuth do OpenAI Codex (ChatGPT Plus).
#
# Fluxo device code:
#   1. start_device_login → retorna code + URL pro usuário
#   2. usuário autoriza no browser
#   3. poll_for_authorization → espera o usuário aprovar
#   4. exchange_for_credential → salva tokens no DB
#
# Durante uso normal do Captain:
#   - valid_access_token → retorna access_token, refrescando se próximo de expirar
class Captain::Codex::AuthService
  CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann'.freeze
  ISSUER = 'https://auth.openai.com'.freeze
  USERCODE_URL = "#{ISSUER}/api/accounts/deviceauth/usercode".freeze
  DEVICE_TOKEN_URL = "#{ISSUER}/api/accounts/deviceauth/token".freeze
  OAUTH_TOKEN_URL = "#{ISSUER}/oauth/token".freeze
  REDIRECT_URI = "#{ISSUER}/deviceauth/callback".freeze
  VERIFY_URL = "#{ISSUER}/codex/device".freeze

  REFRESH_SKEW_SECONDS = 120

  class AuthError < StandardError; end
  class PendingAuthorization < StandardError; end

  class << self
    # Passo 1: solicita um device code.
    def start_device_login
      response = http.post(USERCODE_URL) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = { client_id: CLIENT_ID }.to_json
      end

      raise AuthError, "Failed to request device code: #{response.status} #{response.body}" unless response.success?

      data = JSON.parse(response.body)
      {
        user_code: data.fetch('user_code'),
        device_auth_id: data.fetch('device_auth_id'),
        poll_interval: [3, data['interval'].to_i].max,
        verify_url: VERIFY_URL
      }
    end

    # Passo 3: polling. Retorna { authorization_code, code_verifier } ou raises.
    def poll_once(device_auth_id:, user_code:)
      response = http.post(DEVICE_TOKEN_URL) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = { device_auth_id: device_auth_id, user_code: user_code }.to_json
      end

      case response.status
      when 200
        data = JSON.parse(response.body)
        { authorization_code: data.fetch('authorization_code'), code_verifier: data.fetch('code_verifier') }
      when 403, 404
        raise PendingAuthorization
      else
        raise AuthError, "Polling failed: #{response.status} #{response.body}"
      end
    end

    # Passo 4: troca o authorization_code por tokens e persiste.
    def exchange_for_credential(authorization_code:, code_verifier:)
      response = http.post(OAUTH_TOKEN_URL) do |req|
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = URI.encode_www_form(
          grant_type: 'authorization_code',
          code: authorization_code,
          redirect_uri: REDIRECT_URI,
          client_id: CLIENT_ID,
          code_verifier: code_verifier
        )
      end

      raise AuthError, "Token exchange failed: #{response.status} #{response.body}" unless response.success?

      tokens = JSON.parse(response.body)
      save_credential!(tokens)
    end

    # Retorna access_token válido, fazendo refresh se necessário.
    # Lança AuthError se não houver credencial ativa.
    def valid_access_token
      cred = Captain::CodexCredential.current
      raise AuthError, 'No active Codex credential. Run: rails captain:codex:login' if cred.nil?

      cred = refresh!(cred) if cred.needs_refresh?(skew_seconds: REFRESH_SKEW_SECONDS)
      cred.access_token
    end

    def refresh!(credential)
      response = post_refresh_request(credential.refresh_token)

      unless response.success?
        credential.update!(status: 'expired')
        raise AuthError, "Refresh failed: #{response.status} #{response.body}. Re-run: rails captain:codex:login"
      end

      tokens = JSON.parse(response.body)
      credential.update!(refresh_attributes(tokens, credential))
      credential
    end

    def post_refresh_request(refresh_token)
      http.post(OAUTH_TOKEN_URL) do |req|
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = URI.encode_www_form(
          grant_type: 'refresh_token',
          refresh_token: refresh_token,
          client_id: CLIENT_ID
        )
      end
    end

    def refresh_attributes(tokens, credential)
      {
        access_token: tokens.fetch('access_token'),
        refresh_token: tokens['refresh_token'].presence || credential.refresh_token,
        expires_at: Time.current + tokens['expires_in'].to_i.seconds,
        last_refresh_at: Time.current,
        status: 'active'
      }
    end

    private

    def save_credential!(tokens)
      id_claims = decode_id_token(tokens['id_token'])
      attrs = credential_attributes(tokens, id_claims)

      cred = Captain::CodexCredential.current || Captain::CodexCredential.new
      cred.assign_attributes(attrs)
      cred.save!
      cred
    end

    def credential_attributes(tokens, id_claims)
      openai_auth = id_claims['https://api.openai.com/auth'] || {}
      {
        access_token: tokens.fetch('access_token'),
        refresh_token: tokens.fetch('refresh_token'),
        expires_at: Time.current + tokens['expires_in'].to_i.seconds,
        last_refresh_at: Time.current,
        chatgpt_account_id: openai_auth['chatgpt_account_id'],
        chatgpt_plan_type: openai_auth['chatgpt_plan_type'],
        email: id_claims['email'],
        status: 'active'
      }
    end

    def decode_id_token(jwt)
      return {} if jwt.blank?

      payload_b64 = jwt.split('.')[1]
      return {} if payload_b64.blank?

      JSON.parse(Base64.urlsafe_decode64(payload_b64 + ('=' * (-payload_b64.length % 4))))
    rescue StandardError
      {}
    end

    def http
      Faraday.new do |f|
        f.options.timeout = 30
        f.options.open_timeout = 15
      end
    end
  end
end
