# Tool MCP: retorna FAQs aprovadas de um assistente existente.
#
# Caso de uso: Construtor pergunta "copiar FAQs de outro assistente?".
# Tool retorna lista markdown de Q&A pra usuário avaliar e (próxima
# tool) salvar no spec do novo agente.
class Captain::Mcp::Tools::GetAssistantFaqsTool < Captain::Mcp::Tools::BaseTool
  MAX_FAQS = 50

  class << self
    def name
      'get_assistant_faqs'
    end

    def description
      'Retorna FAQs (perguntas/respostas) aprovadas de um assistente existente. ' \
        'Use quando o usuário decidir copiar FAQs de outro assistente durante ' \
        'criação. Retorna até 50 FAQs em markdown.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          assistant_id: {
            type: 'integer',
            description: 'ID do assistente fonte (pegue via list_assistants).'
          }
        },
        required: ['assistant_id']
      }
    end
  end

  def call(args, context:) # rubocop:disable Metrics/AbcSize, Lint/UnusedMethodArgument
    assistant = Captain::Assistant.find_by(id: args['assistant_id'])
    return error_response("Assistente #{args['assistant_id']} não encontrado.") if assistant.blank?

    faqs = assistant.responses
                    .where(status: 'approved')
                    .order(:id)
                    .limit(MAX_FAQS)

    return text_response("_(#{assistant.name} não tem FAQs aprovados)_") if faqs.empty?

    lines = ["# FAQs de #{assistant.name} (#{faqs.size})", '']
    faqs.each_with_index do |f, i|
      lines << "**#{i + 1}. #{f.question}**"
      lines << f.answer.to_s.gsub(/\s+/, ' ').strip
      lines << ''
    end
    text_response(lines.join("\n"))
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::GetAssistantFaqsTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao buscar FAQs: #{e.message}")
  end
end
