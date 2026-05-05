# Endpoint MCP (Model Context Protocol) HTTP do Captain.
#
#   POST /webhooks/captain/mcp
#
# Hermes Agent (e qualquer cliente MCP) conecta aqui pra invocar tools do
# Captain (add_label, faq_lookup, generate_pix, etc).
#
# Conexão pelo Hermes:
#   hermes mcp add captain-tools --url http://CAPTAIN_HOST/webhooks/captain/mcp
#
# Auth: aceita 2 modos (qualquer um basta):
#   - Bearer token (padrão MCP, recomendado): `Authorization: Bearer <CAPTAIN_MCP_SECRET>`
#     É o que `hermes mcp add --auth header` usa nativamente.
#   - HMAC-SHA256 do body: `X-Hub-Signature-256: sha256=<hex>`
#     Para clientes que preferem assinar o body inteiro.
# Secret compartilhado via env var `CAPTAIN_MCP_SECRET`. Quando vazio,
# validação é desabilitada (PoC/dev).
#
# Multi-tenant: o cliente MCP pode mandar contexto (conversation_id,
# inbox_id, account_id) num campo de extensão chamado `_captain_context`
# dentro de `params` do JSON-RPC. Tools que precisam (add_label etc) leem
# esse contexto pra resolver a conversa correta.
class Webhooks::Captain::McpController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :verify_signature

  def process_payload
    request_body = parse_request_body
    return head :bad_request if request_body.blank?

    response = Captain::Mcp::Server.handle(
      request_body,
      context: extract_context(request_body)
    )

    return head :ok if response.nil? # MCP notifications

    render json: response
  rescue StandardError => e
    Rails.logger.error "[Captain::Mcp] error: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    render json: { jsonrpc: '2.0', error: { code: -32_603, message: 'Internal error' } }, status: :internal_server_error
  end

  private

  def parse_request_body
    JSON.parse(request.raw_post)
  rescue JSON::ParserError
    nil
  end

  def verify_signature
    secret = ENV.fetch('CAPTAIN_MCP_SECRET', nil)
    return true if secret.blank?

    return true if bearer_token_matches?(secret)
    return true if hmac_signature_matches?(secret)

    head :unauthorized
  end

  def bearer_token_matches?(secret)
    auth_header = request.headers['Authorization'].to_s
    return false unless auth_header.start_with?('Bearer ')

    token = auth_header.delete_prefix('Bearer ').strip
    ActiveSupport::SecurityUtils.secure_compare(token, secret)
  end

  def hmac_signature_matches?(secret)
    signature = request.headers['X-Hub-Signature-256'].to_s
    return false if signature.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
    ActiveSupport::SecurityUtils.secure_compare(signature, expected)
  end

  # Cliente MCP pode mandar contexto multi-tenant em params._captain_context.
  # Hermes inclui isso quando chama uma tool, pra Captain saber qual conversation
  # é (já que MCP em si é stateless entre client/server).
  #
  # Fallback: cada profile do Hermes está atrelado a uma unidade
  # (Valentina → Dolce Amore, Jasmine → Prime AL, etc), então também aceitamos
  # contexto via headers HTTP fixos no config.yaml do profile:
  #   X-Captain-Account-Id, X-Captain-Assistant-Id, X-Captain-Inbox-Id.
  # Body wins se houver conflito (override por chamada).
  def extract_context(request_body)
    params = request_body['params'] || {}
    body_ctx = params['_captain_context'] || {}
    body_ctx = {} unless body_ctx.is_a?(Hash)

    extract_header_context.merge(body_ctx.symbolize_keys)
  end

  def extract_header_context
    {
      account_id: header_int('X-Captain-Account-Id'),
      assistant_id: header_int('X-Captain-Assistant-Id'),
      inbox_id: header_int('X-Captain-Inbox-Id')
    }.compact
  end

  def header_int(name)
    value = request.headers[name].to_s
    return nil if value.blank?

    value.to_i
  end
end
