# Tool MCP: busca semântica em FAQs/documentação aprovada pelas gerentes.
#
# Caso de uso típico: cliente pergunta algo que NÃO está na skill estruturada
# do Hermes (ex: aceita pet, formas de pagamento alternativo, política de
# alguma situação específica). Em vez de inventar, Hermes chama esta tool
# e responde com base no FAQ atualizado em tempo real pelo Captain UI.
#
# Reaproveita Captain::Tools::SearchReplyDocumentationService — exatamente
# o mesmo serviço que o orquestrador interno do Captain usava antes,
# garantindo que Hermes vê os mesmos FAQs que o caminho legado veria.
class Captain::Mcp::Tools::FaqLookupTool < Captain::Mcp::Tools::BaseTool
  class << self
    def name
      'faq_lookup'
    end

    def description
      'Busca semântica em FAQs/documentação aprovada pelas gerentes do hotel. ' \
        'Use quando o cliente perguntar algo que NÃO está na sua skill ' \
        '(ex: política de pets, horários especiais, convênios, regras pontuais). ' \
        'Retorna até 5 perguntas/respostas mais próximas semanticamente da query. ' \
        'Se não encontrar nada relevante, prefira transferir pro humano em vez ' \
        'de inventar.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description: 'Pergunta ou tema a buscar em linguagem natural ' \
                         '(ex: aceitam pets, estacionamento coberto, ' \
                         'forma de pagamento sem ser Pix).'
          }
        },
        required: ['query']
      }
    end
  end

  def call(args, context:)
    query = args['query'].to_s.strip
    return error_response('Argumento "query" é obrigatório.') if query.blank?

    account = resolve_account(context)
    return error_response('Account não encontrada no contexto MCP.') if account.blank?

    assistant = resolve_assistant(context, account)
    result = ::Captain::Tools::SearchReplyDocumentationService.new(
      account: account,
      assistant: assistant
    ).execute(query: query)

    text_response(result.presence || 'Nenhum FAQ relevante encontrado pra essa pergunta.')
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::FaqLookupTool] error: #{e.class}: #{e.message}")
    error_response("Falha na busca de FAQ: #{e.message}")
  end

  private

  def resolve_account(context)
    account_id = context[:account_id]
    return nil if account_id.blank?

    Account.find_by(id: account_id)
  end

  def resolve_assistant(context, account)
    assistant_id = context[:assistant_id]
    return nil if assistant_id.blank?

    account.captain_assistants.find_by(id: assistant_id)
  end
end
