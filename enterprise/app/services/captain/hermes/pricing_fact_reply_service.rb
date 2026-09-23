class Captain::Hermes::PricingFactReplyService
  PRICE_INTENT = /\b(valor(?:es)?|preco(?:s)?|tabela|pernoite|diaria|[1-5]\s*h(?:oras?)?|custa|quanto\s+(?:custa|fica|sai|e))\b/i
  OTHER_INTENT = /
    \b(localizacao|endereco|maps|mapa|rota|fotos?|videos?|reserv\w*|vagas?|disponi\w*|pix|pagamento|
    pessoas?|hospedes?|criancas?|pets?|animais?|cafe|inclui|incluso|horario|entrada|saida|check\s*in|check\s*out)\b
  /ix
  UNSUPPORTED_DATE = /\b(segunda|terca|quarta|quinta|sexta|sabado|domingo|feriado|fim\s+de\s+semana|dia\s+\d{1,2})\b/i

  PERIOD_LABELS = {
    '1h' => '1h',
    '2h' => '2h',
    '3h' => '3h',
    '4h' => '4h',
    '5h' => '5h',
    'pernoite_promo' => 'Pernoite',
    'pernoite_integral' => 'Pernoite especial',
    'diaria' => 'Diária'
  }.freeze

  def initialize(conversation:, content:)
    @conversation = conversation
    @content = content.to_s
  end

  def call
    return unless price_request?
    return if unsupported_date?
    return if unit.blank? || unit.pricing_categories.empty?

    body = format_pricing
    return if body.blank?

    Captain::Hermes::KnownFactReply.new(
      kind: :pricing,
      content: body,
      exclusive: !normalized_content.match?(OTHER_INTENT)
    )
  end

  private

  def price_request?
    normalized_content.match?(PRICE_INTENT)
  end

  def unsupported_date?
    normalized_content.match?(UNSUPPORTED_DATE) && normalized_content.exclude?('amanha')
  end

  def format_pricing
    categories = selected_categories
    period = requested_period

    return format_period(categories, period) if period.present?
    return format_category(categories.first) if categories.one?

    format_full_table(categories)
  end

  def format_period(categories, period)
    lines = categories.filter_map do |category|
      amount = price_for(category, period)
      "• #{category_label(category)}: *#{format_money(amount)}*" if amount
    end
    return if lines.empty?

    "#{PERIOD_LABELS.fetch(period)}:\n#{lines.join("\n")}"
  end

  def format_category(category)
    items = available_periods(category).filter_map do |period|
      amount = price_for(category, period)
      "#{PERIOD_LABELS.fetch(period)} *#{format_money(amount)}*" if amount
    end
    return if items.empty?

    "Valores de #{category_label(category)}:\n#{items.join(' | ')}"
  end

  def format_full_table(categories)
    lines = categories.filter_map do |category|
      items = available_periods(category).filter_map do |period|
        amount = price_for(category, period)
        "#{PERIOD_LABELS.fetch(period)} #{format_money(amount)}" if amount
      end
      "• #{category_label(category)}: #{items.join(' | ')}" if items.any?
    end
    return if lines.empty?

    "Valores:\n#{lines.join("\n")}"
  end

  def price_for(category, period)
    result = Captain::Mcp::PricingTables.calculate(
      unit_id: unit.id,
      suite_category: category.key,
      period: period,
      total_guests: 2,
      check_in_at: requested_date
    )
    result[:amount] if result[:error].blank?
  end

  def selected_categories
    matched = unit.pricing_categories.includes(:amounts).find do |category|
      category_names(category).any? { |name| phrase_present?(name) }
    end
    matched ? [matched] : unit.pricing_categories.includes(:amounts).order(:id).to_a
  end

  def category_names(category)
    [category.key.tr('_', ' '), *category.aliases.to_a]
  end

  def phrase_present?(phrase)
    candidate = normalize(phrase)
    normalized_content.match?(/(?<![a-z0-9])#{Regexp.escape(candidate)}(?![a-z0-9])/)
  end

  def requested_period
    return 'pernoite_integral' if normalized_content.match?(/pernoite.*\b(especial|premium)\b|\b(especial|premium).*pernoite/)
    return 'pernoite_promo' if normalized_content.include?('pernoite')
    return 'diaria' if normalized_content.include?('diaria')

    match = normalized_content.match(/\b([1-5])\s*h(?:oras?)?\b/)
    "#{match[1]}h" if match
  end

  def available_periods(category)
    periods = category.amounts.pluck(:period).uniq
    Captain::PricingAmount::PERIODS.select { |period| periods.include?(period) }
  end

  def requested_date
    normalized_content.include?('amanha') ? 1.day.from_now : Time.current
  end

  def unit
    @unit ||= begin
      captain_inbox = @conversation.inbox.captain_inbox
      captain_inbox&.captain_unit || captain_inbox&.captain_assistant&.captain_unit ||
        Captain::Unit.find_by(inbox_id: @conversation.inbox_id)
    end
  end

  def category_label(category)
    category.key.tr('_', ' ').mb_chars.titleize.to_s
  end

  def format_money(amount)
    value = amount.to_f
    formatted = (value % 1).zero? ? value.to_i.to_s : format('%.2f', value).tr('.', ',')
    "R$ #{formatted}"
  end

  def normalized_content
    @normalized_content ||= normalize(@content)
  end

  def normalize(text)
    ActiveSupport::Inflector.transliterate(text.to_s.downcase).squish
  end
end
