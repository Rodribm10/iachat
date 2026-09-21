# Tool MCP: retorna tabela de preços de um assistente existente.
#
# Caso de uso: cotação no atendimento e cópia de tabela durante criação de
# novo agente. No atendimento, a unidade é resolvida pelo contexto MCP.
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
      'Fonte oficial de preços da unidade. Use sempre que o cliente perguntar ' \
        'valor, preço, tabela, pernoite, diária ou permanência; não use FAQ ' \
        'para cotação. Retorna categorias, períodos, dias da semana e regra ' \
        'de pessoa extra. No atendimento, omita assistant_id para usar a ' \
        'unidade do contexto MCP.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          assistant_id: {
            type: 'integer',
            description: 'Opcional. ID do assistente fonte; omita no atendimento ' \
                         'para usar o assistente da conversa atual.'
          }
        }
      }
    end
  end

  def call(args, context:)
    assistant = resolve_assistant(args, context)
    return error_response('Assistente não encontrado no contexto MCP.') if assistant.blank?

    text_response(extract_pricing_markdown(assistant))
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::GetAssistantPricingTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao buscar tabela de preços: #{e.message}")
  end

  private

  def resolve_assistant(args, context)
    context = context.with_indifferent_access
    assistant_id = args['assistant_id'].presence || context[:assistant_id]
    return Captain::Assistant.find_by(id: assistant_id) if assistant_id.present?

    CaptainInbox.find_by(inbox_id: context[:inbox_id])&.captain_assistant
  end

  def extract_pricing_markdown(assistant)
    structured = structured_pricing_for(assistant)
    return structured if structured.present?

    scenario = pricing_scenario_for(assistant)
    return scenario if scenario.present?

    "_(assistente #{assistant.name} não tem tabela de preços estruturada nem em scenario)_"
  end

  # Lookup em Captain::PricingCategory + Captain::PricingAmount (DB).
  def structured_pricing_for(assistant)
    unit = unit_for(assistant)
    return nil if unit.blank?
    return nil if unit.pricing_categories.empty?

    format_structured_table(unit)
  end

  def unit_for(assistant)
    return assistant.captain_unit if assistant.captain_unit_id.present?

    ci = CaptainInbox.find_by(captain_assistant_id: assistant.id)
    return nil if ci.blank?

    Captain::Unit.find_by(id: ci.captain_unit_id) ||
      Captain::Unit.find_by(inbox_id: ci.inbox_id)
  end

  # rubocop:disable Metrics/AbcSize
  def format_structured_table(unit)
    lines = ["# Tabela de preços — #{unit.name} (marca #{unit.brand.name})", '']

    unit.pricing_categories.each do |cat|
      lines << "## #{cat.key.tr('_', ' ').capitalize} (extra a partir da #{cat.extra_person_starts_at}ª pessoa)"
      cat.amounts.group_by { |a| a.day_bucket || 'default' }.each do |bucket, amounts|
        lines << "### #{bucket_label(bucket)}"
        lines << '| Período | Valor |'
        lines << '|---|---|'
        amounts.sort_by { |a| Captain::PricingAmount::PERIODS.index(a.period) || 99 }.each do |a|
          lines << "| #{a.period} | R$ #{a.amount.to_f} |"
        end
        lines << ''
      end
    end

    lines << "**Taxa pessoa extra:** R$ #{unit.extra_person_fee.to_f}" if unit.extra_person_fee.to_f.positive?
    lines.join("\n")
  end
  # rubocop:enable Metrics/AbcSize

  def bucket_label(bucket)
    case bucket
    when 'mon_wed' then 'Seg-Qua'
    when 'thu_sun' then 'Qui-Dom'
    else 'Todos os dias'
    end
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
