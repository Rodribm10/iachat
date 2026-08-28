# Servidor MCP (Model Context Protocol) HTTP do Captain.
#
# Implementa subset suficiente da spec MCP pra Hermes Agent consumir como
# cliente via `hermes mcp add captain-tools --url <url>`. Métodos
# implementados:
#   - initialize       — handshake (cliente apresenta info, server responde
#                        capabilities + serverInfo)
#   - tools/list       — devolve a lista de tools registradas
#   - tools/call       — executa uma tool específica e devolve o resultado
#   - notifications/initialized — no-op (cliente confirma que está pronto)
#   - ping             — no-op (health check)
#
# Não suporta SSE/streaming ainda — modo POST/JSON síncrono basta pro
# caso de uso atual (tools que retornam rápido como add_label, faq_lookup).
#
# Auth/segurança ficam no controller (HMAC), aqui só roteia.
class Captain::Mcp::Server
  PROTOCOL_VERSION = '2024-11-05'.freeze
  SERVER_NAME = 'captain-mcp'.freeze
  SERVER_VERSION = '0.1.0'.freeze

  class << self
    def handle(request, context: {})
      new(context: context).handle(request)
    end
  end

  def initialize(context: {})
    @context = context || {}
  end

  def handle(request)
    rid = request['id']
    method = request['method'].to_s
    params = request['params'] || {}

    dispatch(method, rid, params)
  rescue Captain::Mcp::ToolRegistry::ToolNotFoundError,
         Captain::Mcp::ToolRegistry::ToolNotAllowedError => e
    Rails.logger.warn("[Captain::Mcp::Server] tool rejeitada: #{e.message}")
    error_response(rid, -32_602, e.message)
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::Server] error handling #{method}: #{e.class}: #{e.message}")
    error_response(rid, -32_603, "Internal error: #{e.message}")
  end

  private

  def dispatch(method, rid, params)
    case method
    when 'initialize'                                  then respond(rid, initialize_result(params))
    when 'tools/list'                                  then respond(rid, { tools: Captain::Mcp::ToolRegistry.descriptors(context: context) })
    when 'tools/call'                                  then respond(rid, tools_call(params))
    when 'ping'                                        then respond(rid, {})
    when 'notifications/initialized', 'notifications/cancelled' then nil
    else
      error_response(rid, -32_601, "Method not found: #{method}")
    end
  end

  attr_reader :context

  def initialize_result(_params)
    {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: {
        tools: { listChanged: false }
      },
      serverInfo: {
        name: SERVER_NAME,
        version: SERVER_VERSION
      }
    }
  end

  def tools_call(params)
    name = params['name'].to_s
    args = params['arguments'] || {}
    Captain::Mcp::ToolRegistry.call(name, args, context: context)
  end

  def respond(id, result)
    {
      jsonrpc: '2.0',
      id: id,
      result: result
    }
  end

  def error_response(id, code, message)
    {
      jsonrpc: '2.0',
      id: id,
      error: {
        code: code,
        message: message
      }
    }
  end
end
