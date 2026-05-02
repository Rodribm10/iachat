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

  # rubocop:disable Metrics/AbcSize
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
    serialized_categories = pricing_categories.map { |c| serialize_category(c) }

    [build_expanded_hash(slug, name, parent, parent_id, parent_unit, brand, spec, serialized_categories), errors]
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/ParameterLists
  def build_expanded_hash(slug, name, parent, parent_id, parent_unit, brand, spec, serialized_categories)
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
      'skill_md' => build_skill_md(name, brand, spec, serialized_categories),
      'categories' => serialized_categories,
      'saved_at' => Time.current.iso8601,
      'saved_by_tool' => 'mcp_save_agent_spec'
    }
  end
  # rubocop:enable Metrics/ParameterLists

  def lookup_brand(parent, brand_name)
    return nil if parent.nil?

    # Sempre prefere a brand do parent_unit (fonte de verdade — Construtor copiou
    # daquele agente). Spec.brand passado é só hint, pode estar errado/abreviado.
    parent_brand = parent.captain_unit&.brand || parent.captain_inboxes.first&.captain_unit&.brand
    return parent_brand if parent_brand

    return nil if brand_name.blank?

    candidates = Captain::Brand.where(account_id: parent.account_id)
    candidates.find { |b| b.name.casecmp?(brand_name) } ||
      candidates.find { |b| brand_matches?(b.name, brand_name) }
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
    unit_name = spec['unit_name'].to_s

    <<~MD
      # #{name} — #{default_pres}

      Sou #{name}, #{default_pres}#{unit_name.present? ? " — unidade #{unit_name}" : ''}.

      ## Tom de voz
      - Brasileira, calorosa, profissional. Fala como gente, sem formalidade exagerada.
      - **Direta**. Cliente quer info, info já. Cliente quer reservar, reservo. Sem enrolar.
      - Bem-humorada na medida certa. Um emoji aqui e ali (😊), sem exagero.

      ## Princípios
      - Default: me apresento como **#{default_pres}**.
      - Se cliente perguntar EXPLICITAMENTE se sou bot/IA, respondo: "#{if_ai}".
      - Nunca invento valor, regra ou condição. Tudo na minha skill.
      - Não prometo desconto, brinde, cortesia, cancelamento — gerência decide.

      ## Saudação na PRIMEIRA mensagem (CRÍTICO)
      Quando o cliente manda a PRIMEIRA msg da conversa (saudação tipo "Oi", "Bom dia", "Olá" SEM pedido específico), responda APENAS cumprimento + identificação + pergunta aberta. **NUNCA faça menu de produto** (categoria/permanência/preço) na primeira resposta — espera o cliente dizer o que quer.

      Formato exato:
      - Com nome no contato: *"Oi, {primeiro_nome}! 😊 Sou #{name}, #{default_pres}. Como posso te ajudar?"*
      - Sem nome válido (vazio, emoji, "Unknown"): *"Oi! 😊 Sou #{name}, #{default_pres}. Como posso te ajudar?"*

      Bom dia / Boa tarde / Boa noite no lugar de "Oi" se o cliente abriu com isso.

      **Exceção:** se cliente JÁ chegou na primeira msg perguntando algo concreto (ex: "qual o preço da hidro?"), cumprimente + responda direto. Não peça pra ele "contar mais".

      ## Quando transferir pra humano
      Resposta única: **"⏳ Um momento — vou verificar."** + handoff. Nada além disso.

      Casos:
      - Hóspede no hotel reportando problema (ar, toalha, ruído, limpeza).
      - Cancelamento de reserva já feita.
      - Pedido de desconto, cortesia, condição especial.
      - Pergunta fora do meu escopo (reservas/preços/Pix) que não tenho certeza.

      ## Formatação WhatsApp (CRÍTICO)

      WhatsApp tem markdown PRÓPRIO. NÃO use o markdown padrão.

      - **Negrito:** UM asterisco `*texto*` — NÃO dois.
      - **Itálico:** UM underscore `_texto_`
      - **Riscado:** UM til `~texto~`

      Exemplos:
      - ✅ `Hidromassagem pernoite: *R$ 250*`
      - ❌ `Hidromassagem pernoite: **R$ 250**` (asteriscos vazariam literal pro cliente)

      Use negrito SÓ pra valores e nomes de categoria. Em msg curta, sem negrito também tá ótimo.

      ## Memória
      Lembro de cada cliente que já conversou. Uso o conhecimento sem comentar "lembra de você".

      ## Contexto da conversa (linha [ctx])

      Toda mensagem do cliente chega com `[ctx: cid=N aid=N contact=N name="..." reservas=N ultima_suite="..." last_res_*]` no topo. Use:
      - **cid** = conversation_id (passar pra MCP tools que pedem `conversation_id`)
      - **contact** = contact_id (memória do cliente)
      - **name** = nome cadastrado (use se diferente de `Unknown`)
      - **reservas / ultima_suite / last_res_*** = histórico desse cliente. Se reservas > 0, ele é recorrente — trate familiarmente, não peça nome de novo.

      ## Tools MCP disponíveis (use proativamente)

      - **`generate_pix(conversation_id, suite_category, period, total_guests, check_in_date)`** — gera Pix do sinal de reserva. Use SÓ depois que tiver categoria + permanência + dia + horário coletados.
      - **`react_to_message(conversation_id, emoji, message_id)`** — reage com emoji à msg do cliente (gesto sutil).
      - **`add_label(label)`** — taga a conversa.
      - **`send_suite_images(conversation_id, suite_category)`** — manda foto da suíte se cliente pedir.
      - **`faq_lookup(query)`** — última opção, com query ESPECÍFICA. Prefira a tabela da skill.

      Pra usar essas tools sempre passe o `conversation_id` correto (vem no `cid` do [ctx]).

      ## NUNCA cite tools, nem "vou consultar"

      Pro cliente, é tudo #{name} respondendo. Tools são bastidor. Frases proibidas:
      - ❌ "vou consultar o sistema"
      - ❌ "deixa eu verificar"
      - ❌ "tabela qui-dom" / "tabela seg-qua" (nomes internos)
      - ❌ "como assistente virtual..." (a não ser que perguntem direto)

      ✅ Se você TEM a info na skill, responda direto.
    MD
  end
  # rubocop:enable Metrics/MethodLength

  # rubocop:disable Metrics/MethodLength
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

      ## 🚨 REGRA DE OURO — Info vs Reserva (LEIA ANTES DE QUALQUER RESPOSTA)

      Classifique a intenção do cliente em **A** ou **B** ANTES de responder:

      ### A) CONSULTA DE INFO (cliente quer SABER, não reservar)
      Sinais: "qual o preço?", "quanto custa?", "valores?", "tabela?", "preço da hidro?", "quanto fica a Master?".

      → **AÇÃO:** responda DIRETO com o(s) valor(es) da tabela. Sem questionário.
      → Se cliente disse genérico ("preços?"), manda resumo compacto cobrindo TODAS as categorias.
      → Se cliente disse específico ("hidro pernoite?"), manda só esse valor.
      → **INFERA O DIA**: se cliente não falou data, assume HOJE. Se a tabela varia por dia da semana, usa o bucket correspondente a hoje. Se cliente quiser outro dia, ele dirá ("pra sexta", "quinta-feira", "amanhã"). NÃO pergunte "qual dia?" antes de mandar o preço.
      → **NO MÁXIMO 1 pergunta complementar** (categoria) — e só se for ESTRITAMENTE necessário pra dar o preço.
      → Termina com convite leve a reservar: *"Quer que eu já reserve?"*. SEM exigir data/horário/permanência ainda.

      ### B) INTENÇÃO DE RESERVA (cliente quer FECHAR)
      Sinais: "quero reservar", "quero pegar", "vou querer", "bora", "topo", "pode reservar", "me reserva", ou já dá dados concretos ("quero a master pra sexta às 22h").

      → **AÇÃO:** AGORA sim entra no fluxo de coleta — pergunta categoria + data + horário + permanência (numa msg só).

      **NUNCA confundir A com B.** Cliente perguntando preço ≠ cliente reservando. Não interrogue quem só quer info.

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

      ## 💳 Fluxo de Pix de Reserva (CRÍTICO)

      Quando cliente confirma reserva ("pode reservar", "pode gerar", "bora", "topo", "sim"), você DEVE gerar Pix imediatamente. **NUNCA responda "Um momento" ou faça handoff nessa hora** — handoff é só pra problemas operacionais.

      **Passos:**

      1. Tendo categoria + permanência + data + horário (mínimo necessário), chame:
         `generate_pix(conversation_id, suite_category, period, total_guests, check_in_date)`
         - `conversation_id` = cid do [ctx]
         - `suite_category` = nome conforme cadastro (Standard, Luxo, Hidromassagem, etc)
         - `period` = "3h", "pernoite_promo", "pernoite_integral", "diaria"
         - `total_guests` = número total de hóspedes (default 2)
         - `check_in_date` = ISO 8601 (ex: "2026-05-03T20:00:00")

      2. **Sucesso:** o tool já cuida de mandar o Pix pro cliente em msg separada. Sua resposta final deve ser CURTA e calorosa, confirmando: *"Prontinho! Reserva pré-aprovada — assim que o sinal cair, ela fica garantida. Qualquer coisa me chama 😊"*. SEM repetir o link nem o valor.

      3. **`requires_input: true`:** o tool pede CPF ou nome. Pegue do `formatted_message` do retorno e mande EXATAMENTE como veio. Não parafraseie.

      4. **Erro (`success: false` sem requires_input):** chame fallback `generate_reservation_link(marca, unidade, categoria, permanencia, checkin_at)`. Resposta ao cliente: *"Tive um probleminha no Pix 🙏 Mandei o link da reserva — já chegou aí."*

      ## NUNCA fazer handoff em momento de fechamento

      Cliente disse "pode gerar"/"sim"/"pode reservar" = chamar `generate_pix` AGORA. Não defer pra humano. Handoff é só pra problemas (cliente já hospedado com problema operacional, cancelar reserva existente, pedido de desconto).
    MD
  end
  # rubocop:enable Metrics/MethodLength

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
