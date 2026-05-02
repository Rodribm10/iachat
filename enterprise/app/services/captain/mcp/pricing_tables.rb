# Tabelas de preço por unidade do Captain — fonte de verdade backend pra
# tools MCP que precisam validar valor.
#
# Quando o LLM chama `generate_pix`, ele NÃO informa o valor; apenas
# categoria/período/data. Tool calcula via essa tabela no banco. Isso
# impede que o LLM invente um valor.
#
# Fonte de dados: tabelas Captain::PricingCategory + Captain::PricingAmount,
# escritas pelo admin via UI ou pelo Construtor via script `hermes-provision`.
# Antes de v147 esses dados viviam num arquivo Ruby hardcoded — migrado pra
# DB pra permitir cadastro dinâmico de unidades sem deploy.
module Captain::Mcp::PricingTables
  PERIOD_KEYS = %w[2h 3h 4h 5h pernoite_promo pernoite_integral diaria].freeze
  DAY_BUCKETS = %w[mon_wed thu_sun].freeze
  DEFAULT_TZ = 'America/Sao_Paulo'.freeze

  class << self
    # Retorna {amount:, breakdown:} ou erro {error:} pra uma cobrança.
    # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
    def calculate(unit_id:, suite_category:, period:, total_guests: 2, check_in_at: nil)
      unit = Captain::Unit.find_by(id: unit_id)
      return { error: "Unidade #{unit_id} não cadastrada." } if unit.blank?

      category = find_category(unit, suite_category)
      return { error: "Categoria '#{suite_category}' não reconhecida nesta unidade." } if category.blank?

      period_key = normalize_period(period)
      return { error: "Período '#{period}' inválido. Use: #{PERIOD_KEYS.join(', ')}." } if period_key.blank?

      day_bucket = resolve_day_bucket(check_in_at)
      base, used_bucket = resolve_amount(category, period_key, day_bucket)
      return { error: base } if base.is_a?(String)

      starts_at = category.extra_person_starts_at || 3
      extra_guests = [total_guests.to_i - (starts_at - 1), 0].max
      extra_total = extra_guests * unit.extra_person_fee.to_f
      total = (base + extra_total).round(2)

      {
        amount: total,
        breakdown: {
          unit_id: unit.id,
          suite_category: category.key,
          period: period_key,
          day_bucket: used_bucket,
          base_price: base,
          total_guests: total_guests,
          extra_guests: extra_guests,
          extra_person_fee: unit.extra_person_fee.to_f,
          extra_total: extra_total
        }
      }
    end
    # rubocop:enable Metrics/MethodLength,Metrics/AbcSize

    def categories_for(unit_id)
      Captain::PricingCategory.where(captain_unit_id: unit_id).order(:key).pluck(:key)
    end

    private

    def find_category(unit, raw)
      return nil if raw.blank?

      needle = raw.to_s.downcase.strip.tr('_', ' ').squeeze(' ')
      unit.pricing_categories.find { |cat| cat.matches?(needle) }
    end

    def resolve_amount(category, period_key, day_bucket)
      amounts = category.amounts.where(period: period_key)
      return ["Preço de '#{period_key}' não definido para '#{category.key}'.", nil] if amounts.empty?

      # 1) Tenta match exato no day_bucket
      hit = amounts.find_by(day_bucket: day_bucket)
      return [hit.amount.to_f, day_bucket] if hit

      # 2) Tenta preço flat (day_bucket NULL)
      hit = amounts.find_by(day_bucket: nil)
      return [hit.amount.to_f, nil] if hit

      # 3) Bucket pedido não tem amount + não é flat
      avail = amounts.pluck(:day_bucket).map(&:to_s).reject(&:blank?).uniq.join(', ').presence || 'flat'
      ["'#{category.key}/#{period_key}' não tem preço pro dia escolhido (#{day_bucket}). Disponível: #{avail}.", nil]
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

    def normalize_period(raw)
      key = raw.to_s.downcase.strip.tr('-', '_')
      return key if PERIOD_KEYS.include?(key)

      case key
      when 'pernoite', 'pernoite_normal', 'promocional' then 'pernoite_promo'
      when 'feriado', 'pernoite_feriado', 'sex_sab', 'final_de_semana' then 'pernoite_integral'
      when '3', '3 h', 'tres_horas', 'permanencia', 'permanencia_3h' then '3h'
      when 'diária' then 'diaria'
      end
    end
  end
end
