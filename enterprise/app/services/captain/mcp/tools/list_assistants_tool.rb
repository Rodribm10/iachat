# Tool MCP: lista assistentes existentes pro agente Construtor consultar.
#
# Caso de uso: durante criação de novo agente Hermes via skill socrática,
# o Construtor pergunta "quer copiar tabela de preços de outro assistente?".
# Esta tool retorna todos os assistentes cadastrados com metadata útil pra
# escolha (nome, marca, engine, scenarios count, FAQs count).
#
# Read-only. Scope: account_id obrigatório (vem do header X-Captain-Account-Id
# ou body context).
class Captain::Mcp::Tools::ListAssistantsTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'list_assistants'
    end

    def description
      'Lista todos os assistentes existentes da conta. Use durante criação ' \
        'de novo agente pra oferecer "copiar tabela/regras/FAQs de outro ' \
        'assistente". Retorna nome, id, marca/unidade, engine (interno ou hermes), ' \
        'qtd de scenarios e FAQs pra cada um.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          account_id: {
            type: 'integer',
            description: 'ID da conta. Default: account_id do contexto MCP.'
          }
        }
      }
    end
  end

  def call(args, context:)
    account_id = args['account_id'].presence || context[:account_id]
    return error_response('account_id obrigatório.') if account_id.blank?

    account = Account.find_by(id: account_id)
    return error_response("Account #{account_id} não encontrada.") if account.blank?

    rows = account.captain_assistants.order(:id).map { |a| describe(a) }
    text_response(format_markdown(rows))
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::ListAssistantsTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao listar assistentes: #{e.message}")
  end

  private

  def describe(assistant)
    inboxes = CaptainInbox.where(captain_assistant_id: assistant.id).filter_map(&:inbox)
    units = inboxes.filter_map { |i| Captain::Unit.find_by(inbox_id: i.id) }
    {
      id: assistant.id,
      name: assistant.name,
      engine: assistant.config.to_h['engine_type'].presence || 'internal',
      scenarios: assistant.scenarios.count,
      faqs: assistant.responses.count,
      inboxes: inboxes.map(&:name),
      units: units.map(&:name),
      brand: units.first&.brand&.name
    }
  end

  def format_markdown(rows)
    return '_(nenhum assistente cadastrado nesta conta)_' if rows.empty?

    lines = ['# Assistentes da conta', '']
    rows.each do |r|
      engine_badge = r[:engine] == 'hermes' ? '⚡ Hermes' : '🧠 Captain interno'
      lines << "## ##{r[:id]} — #{r[:name]}  · #{engine_badge}"
      lines << "- Marca: #{r[:brand].presence || '_não vinculada_'}"
      lines << "- Inbox(es): #{r[:inboxes].join(', ').presence || '_nenhuma_'}"
      lines << "- Unidade(s): #{r[:units].join(', ').presence || '_nenhuma_'}"
      lines << "- Scenarios: #{r[:scenarios]} · FAQs: #{r[:faqs]}"
      lines << ''
    end
    lines.join("\n")
  end
end
