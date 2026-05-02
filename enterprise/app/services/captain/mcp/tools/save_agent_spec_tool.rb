# Tool MCP: salva especificação completa de um novo agente Hermes em JSON.
#
# Caso de uso: ao final do fluxo socrático do Construtor, ele junta tudo
# que coletou (persona, marca, tabela, regras, FAQs, identidade da unidade)
# num JSON e chama esta tool pra persistir em /tmp/agent-specs/<slug>.json.
#
# **NÃO cria filesystem do profile Hermes** nem registros no Captain DB.
# Apenas salva a especificação. Provisionamento real é etapa SEPARADA
# (próxima sessão) — Construtor só coleta e prepara o JSON.
#
# Útil pra UI Captain depois listar specs prontas e o admin clicar
# "provisionar" — ou pra revisor humano validar antes de criar.
class Captain::Mcp::Tools::SaveAgentSpecTool < Captain::Mcp::Tools::BaseTool
  SPEC_DIR = '/tmp/agent-specs'.freeze

  class << self
    def name
      'save_agent_spec'
    end

    def description
      'Salva especificação completa de um novo agente Hermes em JSON. Use ao ' \
        'final do fluxo socrático quando tiver coletado TUDO: name, persona, ' \
        'brand, unit, pricing, rules, faqs, identity. Não cria o agente — só ' \
        'salva o spec pra revisão/provisionamento separado depois.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          slug: {
            type: 'string',
            description: 'Slug único pro agente (ex: "jasmine_prime_al"). Lowercase, snake_case. Vai ser nome do arquivo.'
          },
          spec: {
            type: 'object',
            description: 'JSON completo da especificação — persona, marca, unidade, tabela, regras, FAQs, identidade. ' \
                         'Estrutura livre, mas inclua todos os campos que coletou no fluxo.'
          }
        },
        required: %w[slug spec]
      }
    end
  end

  def call(args, context:) # rubocop:disable Metrics/AbcSize, Lint/UnusedMethodArgument
    slug = args['slug'].to_s.strip.downcase.gsub(/[^a-z0-9_]/, '_').squeeze('_')
    return error_response('slug inválido (use lowercase, snake_case, só letras/números/underscore).') if slug.blank? || slug.length < 3

    spec = args['spec']
    return error_response('spec deve ser um objeto JSON.') unless spec.is_a?(Hash)

    FileUtils.mkdir_p(SPEC_DIR)
    path = File.join(SPEC_DIR, "#{slug}.json")
    enriched = spec.merge(
      'slug' => slug,
      'saved_at' => Time.current.iso8601,
      'saved_by_tool' => 'mcp_save_agent_spec'
    )
    File.write(path, JSON.pretty_generate(enriched))

    text_response(
      "Spec do agente '#{slug}' salvo em #{path}. " \
      'Próximo passo (separado): admin revisa o JSON e dispara provisionamento real.'
    )
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::SaveAgentSpecTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao salvar spec: #{e.message}")
  end
end
