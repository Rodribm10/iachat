# Entrega o CEO Digest em um canal Mattermost via Incoming Webhook.
# Formata o digest como um attachment rico (cards coloridos, campos em tabela).
#
# Doc do formato: https://docs.mattermost.com/developer/message-attachments.html
# rubocop:disable Metrics/ClassLength
class Captain::Reports::MattermostDeliveryService
  TIMEOUT_SECONDS = 10
  MAX_TEXT_LENGTH = 4_000 # Mattermost truncates silently above this

  COLOR_GREEN = '#2eb886'.freeze
  COLOR_YELLOW = '#ecb22e'.freeze
  COLOR_RED = '#e01e5a'.freeze

  def initialize(digest:, webhook_url:, channel: nil, username: 'Captain CEO Digest')
    @digest = digest
    @webhook_url = webhook_url
    @channel = channel
    @username = username
  end

  def call
    raise ArgumentError, 'webhook_url is required' if @webhook_url.blank?

    post_and_handle
  end

  private

  def post_and_handle
    response = HTTParty.post(
      @webhook_url,
      body: build_payload.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: TIMEOUT_SECONDS
    )

    unless response.success?
      Rails.logger.error "[CeoDigest::Mattermost] delivery failed #{response.code}: #{response.body.to_s.force_encoding('UTF-8')}"
      return { success: false, status: response.code, body: response.body }
    end

    { success: true, status: response.code }
  rescue StandardError => e
    Rails.logger.error "[CeoDigest::Mattermost] delivery error: #{e.class} #{e.message}"
    { success: false, error: e.message }
  end

  def build_payload
    payload = {
      username: @username,
      icon_emoji: ':bar_chart:',
      text: header_text,
      attachments: build_attachments
    }
    payload[:channel] = @channel if @channel.present?
    payload
  end

  def header_text
    period = "#{format_date(@digest[:period_start])} a #{format_date(@digest[:period_end])}"
    "## :bar_chart: CEO Digest Semanal — **#{@digest[:account_name]}**\n_Período: #{period}_"
  end

  def build_attachments
    return [empty_attachment] if @digest[:empty]

    [
      totals_attachment,
      unit_ranking_attachment,
      ai_performance_attachment,
      satisfaction_attachment,
      opportunities_attachment,
      topics_attachment,
      recommendations_attachment
    ].compact
  end

  def totals_attachment
    t = @digest[:totals]
    delta = format_delta(t[:conversations_delta_pct])

    {
      color: COLOR_GREEN,
      title: ':1234: Números da semana',
      fields: [
        { title: 'Conversas', value: "**#{t[:conversations]}** #{delta}", short: true },
        { title: 'Mensagens', value: "**#{t[:messages]}**", short: true },
        { title: 'Unidades analisadas', value: t[:units_analyzed].to_s, short: true },
        { title: 'Insights gerados', value: t[:insights_analyzed].to_s, short: true }
      ]
    }
  end

  def unit_ranking_attachment
    ranking = @digest[:unit_ranking]
    return nil if ranking.empty?

    lines = ranking.each_with_index.map do |u, idx|
      delta = format_delta(u[:conversations_delta_pct])
      "**#{idx + 1}. #{u[:unit_name]}** — #{u[:conversations]} conversas #{delta}"
    end

    {
      color: COLOR_GREEN,
      title: ':trophy: Ranking por unidade (volume)',
      text: lines.join("\n")
    }
  end

  def ai_performance_attachment
    perf = @digest[:ai_performance]
    return nil if perf.empty?

    text_parts = [ai_performance_lines(perf).join("\n")]
    failures_block = ai_failures_block(perf)
    text_parts << "\n**Principais erros:**\n#{failures_block.join("\n")}" if failures_block.any?

    {
      color: ai_performance_color(perf),
      title: ':robot_face: Performance da IA (Angelina)',
      text: truncate(text_parts.join("\n"))
    }
  end

  def ai_performance_lines(perf)
    perf.map do |u|
      rate = u[:success_rate_pct]
      rate_str = rate ? "#{rate}%" : 'sem dados'
      "#{ai_rate_icon(rate)} **#{u[:unit_name]}** — acerto: #{rate_str} (#{u[:failures_count]} falhas em #{u[:conversations]} conversas)"
    end
  end

  def ai_rate_icon(rate)
    return ':grey_question:' if rate.nil?
    return ':white_check_mark:' if rate >= 85
    return ':warning:' if rate >= 70

    ':x:'
  end

  def ai_failures_block(perf)
    failing = perf.reject { |u| u[:success_rate_pct].nil? || u[:success_rate_pct] >= 85 }
    failing.first(3).flat_map do |u|
      next [] if u[:top_failures].empty?

      ["_#{u[:unit_name]}:_"] + u[:top_failures].map { |f| "• #{f['description']} (#{f['frequency']}x)" }
    end
  end

  def ai_performance_color(perf)
    perf.any? { |u| u[:success_rate_pct].to_f < 70 } ? COLOR_RED : COLOR_YELLOW
  end

  def satisfaction_attachment
    sat = @digest[:satisfaction]
    return nil if sat[:most_dissatisfied].empty? && sat[:most_satisfied].empty?

    dissatisfied_lines = dissatisfied_unit_lines(sat[:most_dissatisfied])
    satisfied_lines = satisfied_unit_lines(sat[:most_satisfied])

    text_parts = []
    text_parts << ":rage: **Onde teve mais reclamação:**\n#{dissatisfied_lines.join("\n")}" if dissatisfied_lines.any?
    text_parts << "\n:heart: **Onde teve mais elogio:**\n#{satisfied_lines.join("\n")}" if satisfied_lines.any?
    return nil if text_parts.empty?

    {
      color: dissatisfied_lines.any? ? COLOR_RED : COLOR_GREEN,
      title: ':thermometer: Satisfação dos clientes',
      text: truncate(text_parts.join("\n"))
    }
  end

  def dissatisfied_unit_lines(units)
    units.first(3).flat_map do |u|
      next [] if u[:complaints_count].zero?

      header = "**#{u[:unit_name]}** — #{u[:complaints_count]} reclamações (#{u[:negative_pct]}% negativo)"
      [header] + u[:top_complaints].map { |c| "• _#{truncate(c, limit: 150)}_" }
    end
  end

  def satisfied_unit_lines(units)
    units.first(3).flat_map do |u|
      next [] if u[:praises_count].zero?

      header = "**#{u[:unit_name]}** — #{u[:praises_count]} elogios (#{u[:positive_pct]}% positivo)"
      [header] + u[:top_praises].map { |p| "• _#{truncate(p, limit: 150)}_" }
    end
  end

  def opportunities_attachment
    opps = @digest[:customer_opportunities]
    return nil if opps.empty?

    lines = opps.first(7).map do |o|
      freq = o['frequency'].to_i
      "• **#{o['opportunity']}** — pedido #{freq}x"
    end

    {
      color: COLOR_YELLOW,
      title: ':bulb: Oportunidades (o que os clientes pediram)',
      text: lines.join("\n")
    }
  end

  def topics_attachment
    fields = [
      topics_field(@digest[:top_topics]),
      faq_gaps_field(@digest[:faq_gaps]),
      complaints_field(@digest[:complaints])
    ].compact
    return nil if fields.empty?

    {
      color: COLOR_YELLOW,
      title: ':speech_balloon: Temas e lacunas',
      fields: fields
    }
  end

  def topics_field(topics)
    return nil if topics.blank?

    {
      title: 'Mais falados',
      value: topics.first(5).map { |t| "• #{t['topic']} (#{t['count']})" }.join("\n"),
      short: true
    }
  end

  def faq_gaps_field(gaps)
    return nil if gaps.blank?

    {
      title: 'Lacunas de FAQ',
      value: gaps.first(5).map { |g| "• #{truncate(g['question'], limit: 80)} (#{g['frequency']}x)" }.join("\n"),
      short: true
    }
  end

  def complaints_field(complaints)
    return nil if complaints.blank?

    {
      title: 'Reclamações recorrentes',
      value: complaints.first(5).map { |c| "• #{truncate(c[:text], limit: 120)}" }.join("\n"),
      short: false
    }
  end

  def recommendations_attachment
    recs = @digest[:recommendations]
    return nil if recs.empty?

    {
      color: COLOR_GREEN,
      title: ':dart: Recomendações da IA',
      text: recs.first(8).map { |r| "• #{r}" }.join("\n")
    }
  end

  def empty_attachment
    {
      color: COLOR_YELLOW,
      title: ':grey_question: Sem dados no período',
      text: 'Não há insights gerados para a semana selecionada. Verifique se o job semanal está agendado e se há conversas nas unidades.'
    }
  end

  def format_date(date)
    return '—' if date.blank?

    begin
      I18n.l(date.to_date, format: :default)
    rescue StandardError
      date.to_s
    end
  end

  def format_delta(pct)
    return '' if pct.nil?

    arrow = if pct.positive?
              ':arrow_up:'
            else
              pct.negative? ? ':arrow_down:' : ':arrow_right:'
            end
    sign = pct.positive? ? '+' : ''
    "(#{arrow} #{sign}#{pct}% vs. semana anterior)"
  end

  def truncate(text, limit: MAX_TEXT_LENGTH)
    text.to_s.length > limit ? "#{text.to_s[0, limit - 3]}..." : text.to_s
  end
end
# rubocop:enable Metrics/ClassLength
