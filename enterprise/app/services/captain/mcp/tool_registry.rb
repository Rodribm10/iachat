# Registry centralizado das tools MCP do Captain.
#
# Adicionar uma tool nova = incluir a classe em TOOLS abaixo. Cada tool
# herda de Captain::Mcp::Tools::BaseTool e responde a .to_mcp_descriptor
# (pra `tools/list`) e #call(args, context:) (pra `tools/call`).
#
# Hermes consulta tools/list pra saber o que pode chamar e tools/call pra
# executar. Toda tool aqui está disponível pra qualquer profile do Hermes
# que se conecte ao MCP server do Captain via `hermes mcp add`.
class Captain::Mcp::ToolRegistry
  TOOLS = [
    Captain::Mcp::Tools::AddLabelTool,
    Captain::Mcp::Tools::FaqLookupTool
    # Captain::Mcp::Tools::GeneratePixTool     — TODO depois MCP base validar
    # Captain::Mcp::Tools::SendSuiteImagesTool — TODO depois MCP base validar
    # Captain::Mcp::Tools::HandoffTool         — fluxo via automation hoje, MCP futuro
  ].freeze

  class << self
    def descriptors
      TOOLS.map(&:to_mcp_descriptor)
    end

    def find(name)
      TOOLS.find { |klass| klass.name == name.to_s }
    end

    def call(name, args, context:)
      klass = find(name)
      raise ArgumentError, "Tool não registrada: #{name}" if klass.nil?

      klass.new.call(args || {}, context: context || {})
    end
  end
end
