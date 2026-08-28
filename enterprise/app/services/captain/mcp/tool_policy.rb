# Resolve quais ferramentas MCP um assistente pode descobrir e executar.
#
# Compatibilidade: chamadas sem assistant_id/inbox_id e assistentes sem a chave
# mcp_tool_allowlist continuam recebendo todas as ferramentas registradas.
# Quando uma identidade é informada, mas não pode ser resolvida, a política
# falha de forma fechada e não libera nenhuma ferramenta.
class Captain::Mcp::ToolPolicy
  attr_reader :assistant

  def initialize(context:, registered_tool_names:)
    @context = (context || {}).to_h.with_indifferent_access
    @registered_tool_names = registered_tool_names.map(&:to_s).freeze
    @assistant = resolve_assistant if scoped_context?
  end

  def allowed_tool_names
    return registered_tool_names unless scoped_context?
    return [] if assistant.nil?
    return registered_tool_names unless assistant.config.key?('mcp_tool_allowlist')

    Array(assistant.mcp_tool_allowlist).map(&:to_s) & registered_tool_names
  end

  def allowed?(tool_name)
    allowed_tool_names.include?(tool_name.to_s)
  end

  private

  attr_reader :context, :registered_tool_names

  def scoped_context?
    context[:assistant_id].present? || context[:inbox_id].present?
  end

  def resolve_assistant
    return assistant_from_id if context[:assistant_id].present?

    assistant_from_inbox
  end

  def assistant_from_id
    scope = Captain::Assistant.where(id: context[:assistant_id])
    scope = scope.where(account_id: context[:account_id]) if context[:account_id].present?
    scope.first
  end

  def assistant_from_inbox
    scope = CaptainInbox.joins(:captain_assistant).where(inbox_id: context[:inbox_id])
    scope = scope.where(captain_assistants: { account_id: context[:account_id] }) if context[:account_id].present?

    scope.first&.captain_assistant
  end
end
