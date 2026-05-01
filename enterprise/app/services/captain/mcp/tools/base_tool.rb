# Interface base pras tools MCP do Captain.
#
# Cada tool concreta herda desta classe e implementa:
#   - .name           — identificador (snake_case)
#   - .description    — texto pro LLM decidir quando chamar
#   - .input_schema   — JSON Schema (Draft 2020-12) dos argumentos
#   - #call(args, context:) — execução real
#
# context é um hash com metadata da invocação (ex: conversation_id,
# inbox_id, account_id) extraído do request MCP. Tools usam isso pra
# resolver entidades do Captain (Conversation, Inbox, etc).
class Captain::Mcp::Tools::BaseTool
  class ExecutionError < StandardError; end

  class << self
    def name
      raise NotImplementedError, "#{self} must implement .name"
    end

    def description
      raise NotImplementedError, "#{self} must implement .description"
    end

    def input_schema
      raise NotImplementedError, "#{self} must implement .input_schema"
    end

    def to_mcp_descriptor
      {
        name: name,
        description: description,
        inputSchema: input_schema
      }
    end
  end

  def call(_args, context:)
    raise NotImplementedError, "#{self.class} must implement #call"
  end

  protected

  def text_response(text)
    {
      content: [{ type: 'text', text: text.to_s }],
      isError: false
    }
  end

  def error_response(message)
    {
      content: [{ type: 'text', text: message.to_s }],
      isError: true
    }
  end
end
