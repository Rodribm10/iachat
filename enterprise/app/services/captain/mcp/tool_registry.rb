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
    Captain::Mcp::Tools::FaqLookupTool,
    Captain::Mcp::Tools::GeneratePixTool,
    Captain::Mcp::Tools::UpdateContactTool,
    Captain::Mcp::Tools::GetContactHistoryTool,
    Captain::Mcp::Tools::CheckPixPaymentTool,
    Captain::Mcp::Tools::SendSuiteImagesTool,
    Captain::Mcp::Tools::RescheduleReservationTool,
    Captain::Mcp::Tools::ReactToMessageTool,
    Captain::Mcp::Tools::CheckSuiteAvailabilityTool,
    # Construtor (admin scope) — usadas pelo profile Hermes "construtor" pra criar novos agentes
    Captain::Mcp::Tools::ListAssistantsTool,
    Captain::Mcp::Tools::GetAssistantPricingTool,
    Captain::Mcp::Tools::GetAssistantFaqsTool,
    Captain::Mcp::Tools::GetAssistantScenarioTool,
    Captain::Mcp::Tools::SaveAgentSpecTool
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
