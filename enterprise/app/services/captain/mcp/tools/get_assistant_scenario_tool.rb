# Tool MCP: retorna o texto completo de um cenário (instruction) de um
# assistente existente.
#
# Caso de uso: Construtor pergunta "copiar identidade/maps/wifi/telefone
# da Lara?". Tool retorna o markdown bruto do scenario solicitado pra o
# Construtor (LLM) extrair os campos relevantes.
#
# Diferente de get_assistant_pricing (que parseia preços) e
# get_assistant_faqs (que lista responses): essa retorna o RAW PROMPT
# pra LLM interpretar livremente.
class Captain::Mcp::Tools::GetAssistantScenarioTool < Captain::Mcp::Tools::BaseTool
  DEFAULT_SCENARIO_TITLE = 'Daniela_Reservas'.freeze
  MAX_CHARS = 20_000

  class << self
    def name
      'get_assistant_scenario'
    end

    def description
      'Retorna o texto MARKDOWN completo de um cenário (prompt) de um ' \
        'assistente existente. Use pra copiar identidade da unidade ' \
        '(endereço, telefone, WhatsApp, maps, wifi, etc), persona ou ' \
        'qualquer outro detalhe que esteja no prompt do agente fonte. ' \
        'Default scenario_title="Daniela_Reservas".'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          assistant_id: {
            type: 'integer',
            description: 'ID do assistente fonte.'
          },
          scenario_title: {
            type: 'string',
            description: "Título do cenário (default: '#{DEFAULT_SCENARIO_TITLE}'). Use list_assistants pra ver opções.",
            default: DEFAULT_SCENARIO_TITLE
          }
        },
        required: ['assistant_id']
      }
    end
  end

  def call(args, context:) # rubocop:disable Lint/UnusedMethodArgument, Metrics/AbcSize
    assistant = Captain::Assistant.find_by(id: args['assistant_id'])
    return error_response("Assistente #{args['assistant_id']} não encontrado.") if assistant.blank?

    title = args['scenario_title'].to_s.presence || DEFAULT_SCENARIO_TITLE
    scenario = assistant.scenarios.find_by(title: title)

    if scenario.blank?
      avail = assistant.scenarios.pluck(:title)
      return error_response(
        "Cenário '#{title}' não existe em #{assistant.name}. Disponíveis: #{avail.join(', ')}."
      )
    end

    text = scenario.instruction.to_s
    text = "#{text.first(MAX_CHARS)}\n\n... [truncado em #{MAX_CHARS} chars] ..." if text.size > MAX_CHARS

    text_response("# Cenário '#{title}' de #{assistant.name}\n\n#{text}")
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::GetAssistantScenarioTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao buscar cenário: #{e.message}")
  end
end
