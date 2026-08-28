# Registry centralizado das tools MCP do Captain.
#
# Adicionar uma tool nova = incluir a classe em TOOLS abaixo. Cada tool
# herda de Captain::Mcp::Tools::BaseTool e responde a .to_mcp_descriptor
# (pra `tools/list`) e #call(args, context:) (pra `tools/call`).
#
# Hermes consulta tools/list pra saber o que pode chamar e tools/call pra
# executar. ToolPolicy aplica o allowlist do Captain::Assistant quando o
# cliente envia assistant_id ou inbox_id no contexto MCP.
class Captain::Mcp::ToolRegistry
  class ToolNotFoundError < StandardError; end
  class ToolNotAllowedError < StandardError; end

  TOOLS = [
    Captain::Mcp::Tools::AddLabelTool,
    Captain::Mcp::Tools::HandoffTool,
    Captain::Mcp::Tools::FaqLookupTool,
    Captain::Mcp::Tools::GeneratePixTool,
    Captain::Mcp::Tools::UpdateContactTool,
    Captain::Mcp::Tools::GetContactHistoryTool,
    Captain::Mcp::Tools::CheckPixPaymentTool,
    Captain::Mcp::Tools::SendSuiteImagesTool,
    Captain::Mcp::Tools::RescheduleReservationTool,
    Captain::Mcp::Tools::ReactToMessageTool,
    Captain::Mcp::Tools::CheckSuiteAvailabilityTool,
    # PIX manual estático (Padova, Express AL) — fluxo paralelo ao Inter
    Captain::Mcp::Tools::VerifyPixProofTool,
    Captain::Mcp::Tools::CreateInternalNoteTool,
    Captain::Mcp::Tools::ConfirmPixManualTool,
    Captain::Mcp::Tools::MarkReservationPendingTool,
    # Construtor (admin scope) — usadas pelo profile Hermes "construtor" pra criar novos agentes
    Captain::Mcp::Tools::ListAssistantsTool,
    Captain::Mcp::Tools::GetAssistantPricingTool,
    Captain::Mcp::Tools::GetAssistantFaqsTool,
    Captain::Mcp::Tools::GetAssistantScenarioTool,
    Captain::Mcp::Tools::SaveAgentSpecTool
    # Captain::Mcp::Tools::HandoffTool         — fluxo via automation hoje, MCP futuro
  ].freeze

  class << self
    def descriptors(context: {})
      allowed_tools(context: context).map(&:to_mcp_descriptor)
    end

    def find(name)
      TOOLS.find { |klass| klass.name == name.to_s }
    end

    def allowed_tool_names(context: {})
      policy(context).allowed_tool_names
    end

    def allowed_tools(context: {})
      allowed_names = allowed_tool_names(context: context)
      TOOLS.select { |klass| allowed_names.include?(klass.name) }
    end

    def call(name, args, context:)
      klass = find(name)
      raise ToolNotFoundError, "Tool não registrada: #{name}" if klass.nil?

      unless policy(context).allowed?(klass.name)
        Rails.logger.warn(
          "[Captain::Mcp::ToolRegistry] tool bloqueada=#{klass.name} " \
          "assistant_id=#{context&.dig(:assistant_id) || context&.dig('assistant_id')} " \
          "inbox_id=#{context&.dig(:inbox_id) || context&.dig('inbox_id')}"
        )
        raise ToolNotAllowedError, "Tool indisponível: #{name}"
      end

      klass.new.call(args || {}, context: context || {})
    end

    private

    def policy(context)
      Captain::Mcp::ToolPolicy.new(
        context: context,
        registered_tool_names: TOOLS.map(&:name)
      )
    end
  end
end
