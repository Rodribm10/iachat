# Tool MCP: salva especificação de um novo agente Hermes EXPANDIDA pro
# formato que /usr/local/bin/hermes-provision consome direto.
#
# Recebe spec do Construtor (formato "referências": persona_source +
# pricing_source apontando pra outro assistant) e expande server-side em:
#   - categories[]: array de {key, aliases, extra_person_starts_at, amounts[]}
#     resolvido a partir de Captain::PricingCategory + Captain::PricingAmount
#     do unit do parent
#   - soul_md: gerado do template + identity + disclosure_policy
#   - skill_md: gerado do template + categories + identity + rules
#   - account_id, marca, unit_name resolvidos
#   - parent_assistant_id setado pra o copied_from_assistant_id (FAQs sombra)
#
# Output: spec pronto pra rodar `cat /tmp/agent-specs/<slug>.json | hermes-provision`.
# rubocop:disable Metrics/ClassLength
class Captain::Mcp::Tools::SaveAgentSpecTool < Captain::Mcp::Tools::BaseTool
  SPEC_DIR = '/tmp/agent-specs'.freeze

  class << self
    def name
      'save_agent_spec'
    end

    def description
      'Salva especificação completa expandida de um novo agente Hermes. ' \
        'Recebe estrutura com referências (pricing_source/persona_source) e ' \
        'expande server-side em categories[]+soul_md+skill_md prontos pra ' \
        'provisionamento. Use ao final do fluxo socrático.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          slug: {
            type: 'string',
            description: 'Slug único pro agente (lowercase, snake_case). Será nome do profile e do arquivo.'
          },
          spec: {
            type: 'object',
            description: 'JSON da especificação — name, brand, unit_name, persona_source, pricing_source, identity, rules, faqs.'
          }
        },
        required: %w[slug spec]
      }
    end
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Lint/UnusedMethodArgument
  def call(args, context:)
    slug = args['slug'].to_s.strip.downcase.gsub(/[^a-z0-9_]/, '_').squeeze('_')
    return error_response('slug inválido (lowercase, snake_case, 3+ chars).') if slug.blank? || slug.length < 3

    spec = args['spec']
    return error_response('spec deve ser um objeto JSON.') unless spec.is_a?(Hash)

    expanded, errors = expand_spec(slug, spec)
    return error_response("Spec inválido após expansão: #{errors.join('; ')}") if errors.any?

    FileUtils.mkdir_p(SPEC_DIR)
    path = File.join(SPEC_DIR, "#{slug}.json")
    File.write(path, JSON.pretty_generate(expanded))

    text_response(
      "✅ Spec EXPANDIDO salvo em #{path}.\n\n" \
      "Conteúdo: #{expanded['categories'].size} categorias, " \
      "soul_md #{expanded['soul_md']&.length || 0} chars, " \
      "skill_md #{expanded['skill_md']&.length || 0} chars.\n\n" \
      "Pra provisionar, rode no terminal:\n" \
      "```\ndocker exec $(docker ps --filter name=iachat_iachat_app -q | head -1) cat #{path} | /usr/local/bin/hermes-provision\n```"
    )
  rescue StandardError => e
    Rails.logger.error("[SaveAgentSpecTool] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    error_response("Erro ao expandir spec: #{e.message}")
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Lint/UnusedMethodArgument

  private

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def expand_spec(slug, spec)
    errors = []
    parent_id = spec.dig('persona_source', 'copied_from_assistant_id') ||
                spec.dig('pricing_source', 'copied_from_assistant_id')
    parent = parent_id ? Captain::Assistant.find_by(id: parent_id) : nil
    errors << "parent assistant_id=#{parent_id} não encontrado" if parent_id && parent.nil?
    return [{}, errors] if errors.any?

    # Resolve marca: spec.brand string → Captain::Brand
    brand_name = spec['brand'] || spec['marca']
    brand = lookup_brand(parent, brand_name)
    errors << "marca '#{brand_name}' não resolvida" if brand.nil?

    # Resolve unit (do parent) pra pricing
    parent_unit = parent_unit_for(parent)
    pricing_categories = parent_unit ? expand_categories(parent_unit) : []
    errors << "unit do parent (id=#{parent_id}) sem categorias de preço cadastradas" if pricing_categories.empty?

    return [{}, errors] if errors.any?

    name = spec['name'].presence || slug.tr('_', ' ').split.map(&:capitalize).join(' ')

    {
      'slug' => slug,
      'name' => name,
      'account_id' => parent.account_id,
      'marca' => brand.name,
      'unit_name' => spec['unit_name'].presence || "#{brand.name} - novo",
      'captain_unit_id' => nil,
      'parent_assistant_id' => parent_id,
      'extra_person_fee' => (parent_unit&.extra_person_fee || 0).to_f,
      'skill_name' => "#{slug.tr('_', '-')}-reservas",
      'humanization' => spec['humanization'] || default_humanization,
      'soul_md' => build_soul_md(name, brand, spec),
      'skill_md' => build_skill_md(name, brand, spec, pricing_categories),
      'categories' => pricing_categories.map { |c| serialize_category(c) },
      'saved_at' => Time.current.iso8601,
      'saved_by_tool' => 'mcp_save_agent_spec'
    }
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

  def lookup_brand(parent, brand_name)
    return nil if parent.nil?

    if brand_name.present?
      hit = Captain::Brand.where(account_id: parent.account_id).find { |b| brand_matches?(b.name, brand_name) }
      return hit if hit
    end
    parent.captain_inboxes.first&.captain_unit&.brand
  end

  def parent_unit_for(parent)
    return nil if parent.nil?
    return parent.captain_unit if parent.captain_unit_id.present?

    ci = parent.captain_inboxes.first
    return nil if ci.nil?

    Captain::Unit.find_by(id: ci.captain_unit_id) || Captain::Unit.find_by(inbox_id: ci.inbox_id)
  end

  def expand_categories(unit)
    unit.pricing_categories.includes(:amounts).to_a
  end

  def serialize_category(cat)
    {
      'key' => cat.key,
      'aliases' => cat.aliases.to_a,
      'extra_person_starts_at' => cat.extra_person_starts_at,
      'amounts' => cat.amounts.map do |a|
        { 'period' => a.period, 'day_bucket' => a.day_bucket, 'amount' => a.amount.to_f }
      end
    }
  end

  def brand_matches?(stored, asked)
    return false if stored.blank? || asked.blank?

    s = stored.downcase
    a = asked.downcase
    s.include?(a) || a.include?(s)
  end

  def default_humanization
    { 'mode' => 'typing_simulation', 'chars_per_second' => 25, 'min_seconds' => 1.5, 'max_seconds' => 6.0 }
  end

  # rubocop:disable Metrics/MethodLength
  def build_soul_md(name, brand, spec)
    identity = spec['identity'] || {}
    disc = identity['disclosure_policy'] || {}
    default_pres = disc['default_presentation'].presence || "atendente do #{brand.name}"
    if_ai = disc['if_explicit_ai_question'].presence || 'assistente virtual'

    <<~MD
      # #{name} — Atendente do #{brand.name}

      Sou #{name}, #{default_pres}. Atendo pelo WhatsApp clientes da rede.

      ## Tom de voz
      - Brasileira, calorosa, profissional. Fala como gente.
      - Direta. Cliente quer reservar, eu reservo.
      - Bem-humorada na medida certa, sem exagero.

      ## Princípios
      - Default: me apresento como **#{default_pres}**.
      - Se cliente perguntar EXPLICITAMENTE se sou bot/IA, respondo: "#{if_ai}".
      - Nunca invento valor, regra ou condição. Tudo na minha skill.
      - Não prometo desconto, brinde, cortesia, cancelamento — gerência decide.

      ## Saudação na primeira mensagem
      - Com nome no contato: *"Oi, {primeiro_nome}! 😊 Sou #{name}, #{default_pres}. Como posso te ajudar?"*
      - Sem nome: *"Oi! 😊 Sou #{name}, #{default_pres}. Como posso te ajudar?"*

      Bom dia / Boa tarde / Boa noite no lugar de "Oi" se cliente abriu com isso.

      ## Quando transferir pra humano
      Resposta única: **"⏳ Um momento — vou verificar."** + handoff.

      Casos: hóspede já no hotel, cancelamento de reserva, pedido de desconto, fora de escopo.

      ## Memória
      Lembro de cada cliente que já conversou. Uso o conhecimento sem comentar 'lembra de você'.
    MD
  end
  # rubocop:enable Metrics/MethodLength

  def build_skill_md(name, brand, spec, categories)
    identity = spec['identity'] || {}
    rules = spec['rules'] || {}

    pricing_md = format_pricing_block(categories)

    <<~MD
      ---
      name: #{name.downcase.tr(' .', '-').squeeze('-')}-reservas
      description: Operação reservas/preços/Pix de #{name} (#{brand.name}).
      when_to_use: Sempre que cliente perguntar sobre preço, reserva, Pix, suítes, horários ou regras.
      ---

      # #{name} — Operação

      Marca: **#{brand.name}**.

      ## Tabela de Preços

      ⚠️ Use direto. Não consulte FAQ pra preço.

      #{pricing_md}

      ## Regras
      - Pernoite: check-in #{rules['pernoite_checkin_from'] || '19h'}, saída #{rules['pernoite_checkout_until'] || '12h'}.
      - Diária: 24h.
      - Pessoa extra começa a pagar a partir da #{rules['extra_person_starts_at'] || 3}ª (base inclui #{rules['base_guests_included'] || 2}).
      - Café da manhã #{rules['breakfast_hours'] || '06h-10h'}. Fora desse horário, #{rules['breakfast_outside_hours'] || 'negociar com a recepção'}.
      - Estacionamento gratuito.

      ## Identidade da Unidade
      #{identity['address'] ? "- Endereço: #{identity['address']}" : ''}
      #{identity['phone'] ? "- Contato: #{identity['phone']}" : ''}
      #{identity['wifi'] && identity.dig('wifi', 'policy') ? "- Wi-Fi: #{identity.dig('wifi', 'policy')}" : ''}
    MD
  end

  def format_pricing_block(categories)
    return '_(sem categorias cadastradas)_' if categories.empty?

    lines = []
    categories.each do |cat|
      lines << "### #{cat['key'].tr('_', ' ').capitalize}"
      grouped = cat['amounts'].group_by { |a| a['day_bucket'] || 'flat' }
      grouped.each do |bucket, amounts|
        label = case bucket
                when 'mon_wed' then 'Seg-Qua'
                when 'thu_sun' then 'Qui-Dom'
                else 'Todos os dias'
                end
        lines << "**#{label}:**"
        amounts.sort_by { |a| Captain::PricingAmount::PERIODS.index(a['period']) || 99 }.each do |a|
          lines << "- #{a['period']}: R$ #{a['amount']}"
        end
        lines << ''
      end
    end
    lines.join("\n")
  end
end
# rubocop:enable Metrics/ClassLength
