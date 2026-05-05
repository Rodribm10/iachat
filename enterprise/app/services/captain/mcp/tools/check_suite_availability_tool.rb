# Tool MCP: consulta status real-time das suítes da unidade.
#
# Reusa as Captain::CustomTool já cadastradas no painel (Ferramentas →
# status_suites_<unidade>) que já apontam pro PlugPlay (oxpi.com.br) com
# auth headers PLUG-PLAY-ID + PLUG-PLAY-TOKEN específicos por unit.
#
# Caso de uso: cliente pediu pra reservar hidromassagem; antes de gerar
# Pix, agente confere se tem suíte livre ("Quer hidro pra hoje 23h? Tenho
# 2 livres no momento" vs "Hidro tá lotada hoje, posso te oferecer Luxo?").
#
# Resolve unit via Assistant.captain_unit_id (preferencial) ou CaptainInbox
# (fallback). Mapping unit → CustomTool é por substring no nome da unit.
class Captain::Mcp::Tools::CheckSuiteAvailabilityTool < Captain::Mcp::Tools::BaseTool
  # Match unit name → sufixo do slug da Captain::CustomTool. Mantém em código
  # porque são 8 unidades fixas; se virar dezenas, vira coluna em Captain::Unit.
  UNIT_NAME_PATTERNS = {
    /qnn|midhaus/i => 'qnn01',
    /dolce/i => 'dolceamore',
    /express/i => 'primeexpress',
    /prime\s*al|águas\s*lindas/i => 'primeal',
    /prime\s*vl|prime\s*ade|cei|asa\s*norte/i => 'primevl'
  }.freeze

  TIMEOUT_SECONDS = 8

  class << self
    def name
      'check_suite_availability'
    end

    def description
      'Consulta em tempo real quais suítes estão livres na unidade. Use ANTES de chamar generate_pix ' \
        'quando o cliente quiser fechar — confirma se a categoria desejada tem disponibilidade. ' \
        'Retorna lista por categoria com contagem livre/ocupada e número da suíte.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID da conversa (cid do [ctx]). Obrigatório pra resolver a unidade.'
          },
          suite_category: {
            type: 'string',
            description: 'Filtra por categoria (ex: "hidromassagem", "luxo", "standard"). Opcional — sem isso traz todas.'
          }
        },
        required: ['conversation_id']
      }
    end
  end

  def call(args, context:)
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]).') if conversation.blank?

    unit = resolve_unit(conversation, context)
    return error_response('Unidade do Captain não vinculada à conversa.') if unit.blank?

    tool = find_status_tool(unit)
    return error_response("Unidade '#{unit.name}' não tem custom_status_suites cadastrado. Avise a gerência.") if tool.nil?

    suites = fetch_suites(tool)
    return error_response('Falha ao consultar status das suítes (timeout/auth). Cliente que aguarde.') if suites.nil?

    summary = summarize(suites, args['suite_category'])
    text_response(summary)
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::CheckSuiteAvailabilityTool] error: #{e.class}: #{e.message}")
    error_response("Erro: #{e.message}")
  end

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  def resolve_unit(conversation, context)
    asst_id = context && (context[:assistant_id] || context['assistant_id'])
    if asst_id
      asst = Captain::Assistant.find_by(id: asst_id)
      return asst.captain_unit if asst&.captain_unit_id.present?
    end
    ci = CaptainInbox.find_by(inbox_id: conversation.inbox_id)
    ci&.captain_unit
  end

  def find_status_tool(unit)
    suffix = UNIT_NAME_PATTERNS.find { |re, _| re.match?(unit.name.to_s) }&.last
    return nil if suffix.blank?

    Captain::CustomTool.find_by(account_id: unit.account_id,
                                slug: "custom_status_suites_#{suffix}",
                                enabled: true)
  end

  def fetch_suites(tool)
    headers = headers_for(tool)
    response = HTTParty.get(tool.endpoint_url, headers: headers, timeout: TIMEOUT_SECONDS)
    return nil unless response.success?

    parsed = JSON.parse(response.body)
    return nil unless parsed.is_a?(Array)

    parsed
  rescue HTTParty::Error, Net::ReadTimeout, Net::OpenTimeout, JSON::ParserError => e
    Rails.logger.warn("[Captain::Mcp::CheckSuiteAvailabilityTool] fetch falhou: #{e.class}: #{e.message}")
    nil
  end

  def headers_for(tool)
    return {} unless tool.auth_type == 'custom_headers'

    list = tool.auth_config.to_h['headers'].to_a
    list.each_with_object({}) { |h, acc| acc[h['name'].to_s] = h['value'].to_s }
  end

  # Agrupa por classe e mostra livre/ocupada + nº das suítes livres. Filtra
  # por categoria se passado. Retorno é texto curto pro LLM repassar resumido.
  def summarize(suites, filter_category)
    grouped = group_filtered(suites, filter_category)
    return "Nenhuma suíte da categoria '#{filter_category}' nesta unidade." if filter_category.present? && grouped.empty?

    lines = grouped.map { |classe, list| summary_line(classe, list) }
    header = filter_category.present? ? "Status #{filter_category} agora:" : 'Status das suítes agora:'
    [header, *lines].join("\n")
  end

  def group_filtered(suites, filter_category)
    grouped = suites.group_by { |s| s['classe'].to_s.upcase.strip }
    return grouped if filter_category.blank?

    grouped.select { |k, _| k.include?(filter_category.to_s.upcase) }
  end

  def summary_line(classe, list)
    livres = list.select { |s| status_livre?(s) }
    ocupadas = list.size - livres.size
    refs = livres.map { |s| s['ref'].to_s }.reject(&:blank?).first(8).join(', ')
    suffix = livres.any? ? " — #{refs}" : ''
    "- #{classe.titleize}: #{livres.size} livre(s) / #{ocupadas} ocupada(s)#{suffix}"
  end

  def status_livre?(suite)
    return false if suite['isOcupado']
    return true if suite['statusId'] == 1
    return true if suite['status'].to_s.casecmp('Livre').zero?

    false
  end
end
