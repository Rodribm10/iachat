# Tool MCP: retorna tabela de preços de um assistente existente.
#
# Caso de uso: Construtor copia tabela durante criação de novo agente
# (mesma marca → mesma tabela).
#
# Estratégia de leitura (em ordem de tentativa):
#  1. Se assistant tem unit vinculada e Captain::Mcp::PricingTables
#     conhece essa unit → retorna tabela estruturada (Hermes-friendly)
#  2. Senão tenta extrair markdown de scenarios do assistant (caminho
#     legado — Captain interno usa scenarios pra guardar tabela)
#  3. Senão retorna mensagem de "não encontrado"
class Captain::Mcp::Tools::GetAssistantPricingTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'get_assistant_pricing'
    end

    def description
      'Retorna a tabela de preços de um assistente existente em markdown. ' \
        'Use quando o usuário (na criação de novo agente) decidir copiar ' \
        'a tabela de outro assistente. Retorna estrutura categórias × períodos ' \
        'com regras de pessoa extra.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          assistant_id: {
            type: 'integer',
            description: 'ID do assistente fonte. Pegue via list_assistants.'
          }
        },
        required: ['assistant_id']
      }
    end
  end

  def call(args, context:) # rubocop:disable Lint/UnusedMethodArgument
    assistant = Captain::Assistant.find_by(id: args['assistant_id'])
    return error_response("Assistente #{args['assistant_id']} não encontrado.") if assistant.blank?

    text_response(extract_pricing_markdown(assistant))
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::GetAssistantPricingTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao buscar tabela de preços: #{e.message}")
  end

  private

  def extract_pricing_markdown(assistant)
    structured = structured_pricing_for(assistant)
    return structured if structured.present?

    scenario = pricing_scenario_for(assistant)
    return scenario if scenario.present?

    "_(assistente #{assistant.name} não tem tabela de preços estruturada nem em scenario)_"
  end

  # Lookup em Captain::Mcp::PricingTables (Hermes-side hardcoded).
  def structured_pricing_for(assistant)
    inbox = CaptainInbox.find_by(captain_assistant_id: assistant.id)
    return nil if inbox.blank?

    unit = Captain::Unit.find_by(inbox_id: inbox.inbox_id)
    return nil if unit.blank?

    table = Captain::Mcp::PricingTables::TABLES[unit.id]
    return nil if table.blank?

    format_structured_table(unit, table)
  end

  def format_structured_table(unit, table)
    lines = ["# Tabela de preços — #{unit.name}", '']
    lines << '| Categoria | 3h | Pernoite Promo | Pernoite Integral | Diária | Pessoa extra a partir |'
    lines << '|---|---|---|---|---|---|'
    table[:categories].each do |key, data|
      prices = data[:prices]
      lines << "| #{key.tr('_', ' ').capitalize} | #{prices['3h']} | #{prices['pernoite_promo']} | " \
               "#{prices['pernoite_integral']} | #{prices['diaria']} | #{data[:extra_person_starts_at]}ª pessoa |"
    end
    lines << ''
    lines << "**Taxa pessoa extra:** R$ #{table[:extra_person_fee]}"
    lines.join("\n")
  end

  # Captain interno guarda a tabela no instruction de algum scenario
  # (geralmente o de reservas/preços). Retorna o markdown bruto pra
  # usuário copiar ou Construtor parsear.
  def pricing_scenario_for(assistant)
    candidate = assistant.scenarios.where('LOWER(title) ~ ?', '(preç|tabela|reserva|valor)').first ||
                assistant.scenarios.first
    return nil if candidate.blank?

    "# Scenario fonte — #{candidate.title}\n\n#{candidate.instruction}"
  end
end
