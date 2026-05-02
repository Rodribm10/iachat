# Tabelas de preço por unidade do Captain — fonte de verdade backend pra
# tools MCP que precisam validar valor. Espelha o que está nos prompts/skills
# das assistentes (Valentina, Jasmines, etc), mas centralizada e auditável.
#
# Quando o LLM chama `generate_pix`, ele NÃO informa o valor; apenas
# categoria/período. Tool calcula via essa tabela. Isso impede que o LLM
# invente um valor (ex: "aplicou desconto VIP" sozinho).
#
# Estrutura: TABLES[captain_unit_id] = {
#   categories: {
#     '<categoria_key>' => {
#       # Preço por período. Aceita 2 formatos:
#       #   1) Valor único (motel sem variação por dia da semana):
#       #        prices: { '3h' => 85.0, 'pernoite_promo' => 110.0 }
#       #   2) Hash por bucket de dia da semana (hotel: qui-dom caro):
#       #        prices: { '3h' => { 'mon_wed' => 50.0, 'thu_sun' => 65.0 } }
#       #   Buckets aceitos: 'mon_wed' (seg-qua) e 'thu_sun' (qui-dom).
#       prices: { '3h' => 85, ... },
#       aliases: ['apto', 'standard', ...]
#     }
#   },
#   extra_person_fee: 45,
#   extra_person_rules: { '<categoria_key>' => starts_at_guest_n }
# }
# rubocop:disable Metrics/ModuleLength
module Captain::Mcp::PricingTables
  PERIOD_KEYS = %w[2h 3h 4h 5h pernoite_promo pernoite_integral diaria].freeze
  # mon_wed cobre wday 1,2,3 (seg-qua); thu_sun cobre wday 4,5,6,0 (qui-dom).
  DAY_BUCKETS = %w[mon_wed thu_sun].freeze
  DEFAULT_TZ = 'America/Sao_Paulo'.freeze

  TABLES = {
    # Motel Dolce Amore — Ponta Negra, Natal/RN (captain_unit_id=4)
    4 => {
      currency: 'BRL',
      extra_person_fee: 45.0,
      # Por categoria, a partir de qual hóspede a taxa começa a contar.
      # Ex: "starts_at_guest_n=3" significa que 3ª pessoa em diante paga.
      # Default 3 — base do quarto inclui 2 pessoas (casal).
      categories: {
        'apartamento' => {
          prices: { '3h' => 85.0, 'pernoite_promo' => 110.0, 'pernoite_integral' => 155.0, 'diaria' => 290.0 },
          extra_person_starts_at: 3,
          aliases: ['apto', 'standard', 'apartamento standard', 'apartamento_standard']
        },
        'suite_master' => {
          prices: { '3h' => 90.0, 'pernoite_promo' => 130.0, 'pernoite_integral' => 180.0, 'diaria' => 340.0 },
          extra_person_starts_at: 3,
          aliases: ['master', 'suite master', 'suíte master', '2 andares']
        },
        'suite_luxo' => {
          prices: { '3h' => 90.0, 'pernoite_promo' => 130.0, 'pernoite_integral' => 180.0, 'diaria' => 340.0 },
          extra_person_starts_at: 3,
          aliases: ['luxo', 'suite luxo', 'suíte luxo', 'classica', 'clássica']
        },
        'suite_tematica' => {
          prices: { '3h' => 90.0, 'pernoite_promo' => 130.0, 'pernoite_integral' => 180.0, 'diaria' => 340.0 },
          extra_person_starts_at: 3,
          aliases: ['tematica', 'temática', 'suite tematica', 'suíte temática']
        },
        'mini_chale_45' => {
          prices: { '3h' => 100.0, 'pernoite_promo' => 140.0, 'pernoite_integral' => 190.0, 'diaria' => 400.0 },
          extra_person_starts_at: 3,
          aliases: ['mini chale', 'mini chalé', 'chale 45', 'chalé 45', 'mini chalé 45', 'mini_chale']
        },
        'chale_2_suites' => {
          prices: { '3h' => 165.0, 'pernoite_promo' => 240.0, 'pernoite_integral' => 350.0, 'diaria' => 490.0 },
          extra_person_starts_at: 4,
          aliases: ['chale 2', 'chalé 2', 'chale 2 suites', 'chalé 2 suítes', 'chale_2', '2 suites']
        },
        'suite_ouro' => {
          prices: { '3h' => 230.0, 'pernoite_promo' => 340.0, 'pernoite_integral' => 440.0, 'diaria' => 830.0 },
          extra_person_starts_at: 4,
          aliases: ['ouro', 'suite ouro', 'suíte ouro']
        },
        'chale_master_4_suites' => {
          prices: { '3h' => 360.0, 'pernoite_promo' => 510.0, 'pernoite_integral' => 580.0, 'diaria' => 1240.0 },
          extra_person_starts_at: 8,
          aliases: ['chale master', 'chalé master', 'master 4 suites', 'chalé master 4 suítes', 'chale_master', '4 suites']
        }
      }
    },
    # Hotel 1001 Noites Express — Águas Lindas/GO (captain_unit_id=5)
    # Preço varia por dia da semana (mon_wed = seg-qua / thu_sun = qui-dom).
    # Diária e Família são flat (mesmo preço todos os dias).
    5 => {
      currency: 'BRL',
      extra_person_fee: 0.0,
      categories: {
        'standard' => {
          prices: {
            '2h' => { 'mon_wed' => 40.0, 'thu_sun' => 50.0 },
            '3h' => { 'mon_wed' => 50.0, 'thu_sun' => 65.0 },
            '4h' => { 'mon_wed' => 60.0, 'thu_sun' => 80.0 },
            'pernoite_promo' => { 'mon_wed' => 100.0, 'thu_sun' => 120.0 },
            'diaria' => 150.0
          },
          extra_person_starts_at: 3,
          aliases: ['standard', 'comum', 'básica', 'basica', 'apartamento standard']
        },
        'master' => {
          prices: {
            '2h' => { 'mon_wed' => 50.0, 'thu_sun' => 60.0 },
            '3h' => { 'mon_wed' => 60.0, 'thu_sun' => 75.0 },
            '4h' => { 'mon_wed' => 70.0 },
            '5h' => { 'thu_sun' => 85.0 },
            'pernoite_promo' => { 'mon_wed' => 120.0, 'thu_sun' => 140.0 },
            'diaria' => 160.0
          },
          extra_person_starts_at: 3,
          aliases: ['master', 'melhor', 'suite master', 'suíte master']
        },
        'singles' => {
          prices: {
            'pernoite_promo' => { 'mon_wed' => 80.0, 'thu_sun' => 110.0 },
            'diaria' => 130.0
          },
          extra_person_starts_at: 99,
          aliases: %w[singles single sozinho]
        },
        'familia' => {
          prices: {
            'pernoite_promo' => 160.0,
            'diaria' => 190.0
          },
          extra_person_starts_at: 99,
          aliases: %w[familia família familiar]
        },
        'singles_duplo' => {
          prices: {
            'pernoite_promo' => { 'mon_wed' => 180.0, 'thu_sun' => 220.0 },
            'diaria' => 250.0
          },
          extra_person_starts_at: 99,
          aliases: ['singles duplo', 'singles_duplo', 'casal', 'duplo']
        }
      }
    }
  }.freeze

  class << self
    # Retorna {amount:, breakdown:} ou erro {error:} pra uma cobrança.
    # period: '3h' | 'pernoite_promo' | 'pernoite_integral' | 'diaria'
    # check_in_at: Time/String ISO8601. Determina o bucket de dia da semana
    #              quando o preço varia (mon_wed/thu_sun). Default: agora.
    # total_guests: número TOTAL de hóspedes — a função calcula extras
    #               baseado em extra_person_starts_at.
    # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    def calculate(unit_id:, suite_category:, period:, total_guests: 2, check_in_at: nil)
      table = TABLES[unit_id]
      return { error: "Unidade #{unit_id} não tem tabela de preços cadastrada." } if table.blank?

      cat_key, cat_data = find_category(table, suite_category)
      return { error: "Categoria '#{suite_category}' não reconhecida nesta unidade." } if cat_data.blank?

      period_key = normalize_period(period)
      return { error: "Período '#{period}' inválido. Use: #{PERIOD_KEYS.join(', ')}." } if period_key.blank?

      raw = cat_data[:prices][period_key]
      return { error: "Preço de '#{period_key}' não definido para '#{cat_key}'." } if raw.blank?

      day_bucket = resolve_day_bucket(check_in_at)
      base, used_bucket = resolve_price(raw, day_bucket, period_key, cat_key)
      return { error: base } if base.is_a?(String)

      starts_at = cat_data[:extra_person_starts_at] || 3
      extra_guests = [total_guests.to_i - (starts_at - 1), 0].max
      extra_total = extra_guests * table[:extra_person_fee]
      total = (base + extra_total).round(2)

      {
        amount: total,
        breakdown: {
          unit_id: unit_id,
          suite_category: cat_key,
          period: period_key,
          day_bucket: used_bucket,
          base_price: base,
          total_guests: total_guests,
          extra_guests: extra_guests,
          extra_person_fee: table[:extra_person_fee],
          extra_total: extra_total
        }
      }
    end

    def categories_for(unit_id)
      TABLES.dig(unit_id, :categories)&.keys || []
    end

    private

    # Recebe Numeric (preço único) ou Hash{bucket=>preço}. Retorna [valor, bucket]
    # ou [erro_string, nil] se o bucket pedido não tiver preço cadastrado.
    def resolve_price(raw, day_bucket, period_key, cat_key)
      return [raw.to_f, nil] if raw.is_a?(Numeric)

      return ["Estrutura de preço inválida pra '#{cat_key}/#{period_key}'.", nil] unless raw.is_a?(Hash)

      price = raw[day_bucket] || raw[day_bucket.to_s]
      if price.blank?
        avail = raw.keys.map(&:to_s).join(', ')
        return ["'#{cat_key}/#{period_key}' não tem preço pro dia escolhido (#{day_bucket}). Disponível: #{avail}.", nil]
      end

      [price.to_f, day_bucket]
    end

    # mon_wed: wday 1,2,3 (seg, ter, qua)
    # thu_sun: wday 4,5,6,0 (qui, sex, sáb, dom)
    def resolve_day_bucket(check_in_at)
      time =
        case check_in_at
        when nil then Time.current.in_time_zone(DEFAULT_TZ)
        when Time, ActiveSupport::TimeWithZone, DateTime then check_in_at.in_time_zone(DEFAULT_TZ)
        else Time.zone.parse(check_in_at.to_s)&.in_time_zone(DEFAULT_TZ) || Time.current.in_time_zone(DEFAULT_TZ)
        end

      [1, 2, 3].include?(time.wday) ? 'mon_wed' : 'thu_sun'
    end

    def find_category(table, raw)
      needle = raw.to_s.downcase.strip.tr('_', ' ').squeeze(' ')
      return [nil, nil] if needle.blank?

      table[:categories].each do |key, data|
        candidates = ([key.tr('_', ' ')] + data[:aliases].to_a).map { |c| c.to_s.downcase.strip }
        return [key, data] if candidates.any?(needle)
      end

      [nil, nil]
    end

    def normalize_period(raw)
      key = raw.to_s.downcase.strip.tr('-', '_')
      return key if PERIOD_KEYS.include?(key)

      # aceita variações comuns
      case key
      when 'pernoite', 'pernoite_normal', 'promocional' then 'pernoite_promo'
      when 'feriado', 'pernoite_feriado', 'sex_sab', 'final_de_semana' then 'pernoite_integral'
      when '3', '3 h', 'tres_horas', 'permanencia', 'permanencia_3h' then '3h'
      when 'diária' then 'diaria'
      end
    end
    # rubocop:enable Metrics/MethodLength,Metrics/AbcSize
  end
end
# rubocop:enable Metrics/ModuleLength
