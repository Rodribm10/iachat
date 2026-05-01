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
# Auth: HMAC-SHA256 do body via header `X-Hub-Signature-256`, secret
# compartilhado via env var `CAPTAIN_MCP_SECRET` (igual ao padrão de
# `hermes_callback`). Quando vazio, validação é desabilitada (PoC/dev).
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

    signature = request.headers['X-Hub-Signature-256'].to_s
    return head :unauthorized if signature.blank?

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, request.raw_post)}"
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(signature, expected)

    true
  end

  # Cliente MCP pode mandar contexto multi-tenant em params._captain_context.
  # Hermes inclui isso quando chama uma tool, pra Captain saber qual conversation
  # é (já que MCP em si é stateless entre client/server).
  def extract_context(request_body)
    params = request_body['params'] || {}
    ctx = params['_captain_context'] || {}
    return {} unless ctx.is_a?(Hash)

    ctx.symbolize_keys
  end
end
