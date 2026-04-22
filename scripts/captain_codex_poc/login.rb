#!/usr/bin/env ruby
# Device code flow OAuth com OpenAI — reutiliza client_id do Hermes.
# Salva tokens em scripts/captain_codex_poc/tokens.json.

require 'net/http'
require 'uri'
require 'json'
require 'time'

CLIENT_ID = 'app_EMoamEEZ73f0CkXaXp7hrann'.freeze
ISSUER = 'https://auth.openai.com'.freeze
TOKENS_PATH = File.expand_path('tokens.json', __dir__).freeze

def http_json(method, url, body: nil, headers: {}, form: false)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 30

  req_class = method == :get ? Net::HTTP::Get : Net::HTTP::Post
  req = req_class.new(uri)
  headers.each { |k, v| req[k] = v }

  if body
    if form
      req['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = URI.encode_www_form(body)
    else
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate(body)
    end
  end

  resp = http.request(req)
  [resp.code.to_i, (resp.body.nil? || resp.body.empty? ? {} : (JSON.parse(resp.body) rescue { 'raw' => resp.body }))]
end

puts '=== Captain Codex OAuth — Device Flow ==='
puts

# Passo 1: Pedir device code
puts '[1/4] Solicitando device code...'
status, data = http_json(:post, "#{ISSUER}/api/accounts/deviceauth/usercode", body: { client_id: CLIENT_ID })
abort "Falhou no device code (HTTP #{status}): #{data}" unless status == 200

user_code = data.fetch('user_code')
device_auth_id = data.fetch('device_auth_id')
poll_interval = [3, (data['interval'] || 5).to_i].max

puts
puts '[2/4] Abra o browser na URL abaixo e cole o código:'
puts
puts "   URL:  \e[36m#{ISSUER}/codex/device\e[0m"
puts "   Code: \e[93m#{user_code}\e[0m"
puts
puts "Aguardando autorização (timeout 15min, Ctrl+C para cancelar)..."

# Passo 2: Polling
auth_code = nil
verifier = nil
deadline = Time.now + (15 * 60)

loop do
  abort "\nTimeout de 15min atingido." if Time.now > deadline
  sleep poll_interval
  code, resp = http_json(:post, "#{ISSUER}/api/accounts/deviceauth/token", body: {
    device_auth_id: device_auth_id,
    user_code: user_code
  })

  case code
  when 200
    auth_code = resp.fetch('authorization_code')
    verifier = resp.fetch('code_verifier')
    break
  when 403, 404
    print '.'
    next
  else
    abort "\nErro no polling (HTTP #{code}): #{resp}"
  end
end

puts "\n[3/4] Autorização recebida, trocando por tokens..."

# Passo 3: Exchange code -> tokens
redirect_uri = "#{ISSUER}/deviceauth/callback"
status, tokens = http_json(:post, "#{ISSUER}/oauth/token", body: {
  grant_type: 'authorization_code',
  code: auth_code,
  redirect_uri: redirect_uri,
  client_id: CLIENT_ID,
  code_verifier: verifier
}, form: true)

abort "Token exchange falhou (HTTP #{status}): #{tokens}" unless status == 200

access_token = tokens.fetch('access_token')
refresh_token = tokens.fetch('refresh_token')
expires_in = Integer(tokens['expires_in'] || 3600)
expires_at = Time.now + expires_in

File.write(TOKENS_PATH, JSON.pretty_generate({
  access_token: access_token,
  refresh_token: refresh_token,
  expires_at: expires_at.iso8601
}))

puts
puts "[4/4] Sucesso!"
puts "   Tokens salvos em: #{TOKENS_PATH}"
puts "   Access token expira em: #{expires_at}"
puts
puts "Próximo passo: ruby scripts/captain_codex_poc/test_chat.rb"
