# Consolida os insights semanais de uma conta em um digest executivo
# pronto pra enviar ao CEO (Mattermost, email, etc).
#
# Conceito de "unidade" no digest = 1 inbox (canal) do Chatwoot.
# Captain::Unit (marca) é usado como fallback quando não há insights por inbox.
# Retorna um hash com rankings, variações WoW e blocos temáticos
# (sem formatação — formatação fica nos adapters de delivery).
# rubocop:disable Metrics/ClassLength
class Captain::Reports::CeoDigestService
  def initialize(account:, period_start: nil, period_end: nil)
    @account = account
    @period_end = period_end || Date.yesterday
    @period_start = period_start || (@period_end - 6.days)
  end

  def call
    insights = fetch_insights(@period_start, @period_end)
    return empty_digest if insights.empty?

    previous_insights = fetch_insights(@period_start - 7.days, @period_end - 7.days)
    build_digest(insights, previous_insights)
  end

  def build_digest(insights, previous_insights)
    ctx = build_context(insights, previous_insights)
    header_block(ctx).merge(unit_blocks(ctx)).merge(aggregate_blocks(ctx))
  end

  def build_context(insights, previous_insights)
    unit_insights = pick_unit_scope(insights)
    {
      insights: insights,
      unit_insights: unit_insights,
      prev_unit_insights: pick_unit_scope(previous_insights),
      global: global_insight(insights),
      prev_global: global_insight(previous_insights),
      aggregate_source: unit_insights.presence || insights
    }
  end

  def header_block(_ctx)
    {
      account_id: @account.id,
      account_name: @account.name,
      period_start: @period_start,
      period_end: @period_end
    }
  end

  def unit_blocks(ctx)
    {
      totals: build_totals(ctx[:unit_insights], ctx[:prev_unit_insights], ctx[:global], ctx[:prev_global]),
      unit_ranking: build_unit_ranking(ctx[:unit_insights], ctx[:prev_unit_insights]),
      ai_performance: build_ai_performance(ctx[:unit_insights]),
      satisfaction: build_satisfaction(ctx[:unit_insights]),
      period_summaries: build_period_summaries(ctx[:unit_insights])
    }
  end

  def aggregate_blocks(ctx)
    source = ctx[:aggregate_source]
    {
      top_topics: aggregate_top_items(source, 'top_topics', 'topic', 'count', limit: 10),
      customer_opportunities: aggregate_top_items(source, 'customer_opportunities', 'opportunity', 'frequency', limit: 10),
      faq_gaps: aggregate_top_items(source, 'faq_gaps', 'question', 'frequency', limit: 10),
      complaints: aggregate_text_highlights(source, 'complaints', limit: 10),
      praises: aggregate_text_highlights(source, 'praises', limit: 10),
      most_requested_suites: aggregate_top_items(source, 'most_requested_suites', 'suite', 'count', limit: 5),
      recommendations: aggregate_recommendations(source, limit: 10)
    }
  end

  private

  # Prioriza insights por-inbox (conceito de unidade do usuário).
  # Se não houver insights por-inbox, cai pra insights por-captain_unit.
  # Nunca mistura os dois — evita dupla contagem.
  def pick_unit_scope(insights)
    by_inbox = insights.select { |i| i.inbox_id.present? }
    return by_inbox if by_inbox.any?

    insights.select { |i| i.captain_unit_id.present? && i.inbox_id.blank? }
  end

  def global_insight(insights)
    insights.find { |i| i.inbox_id.blank? && i.captain_unit_id.blank? }
  end

  def fetch_insights(period_start, period_end)
    Captain::ConversationInsight
      .where(account_id: @account.id)
      .done
      .for_period(period_start, period_end)
      .includes(:captain_unit, :inbox)
      .to_a
  end

  def build_totals(unit_insights, prev_unit_insights, global, prev_global)
    current_conv = global&.conversations_count || unit_insights.sum(&:conversations_count)
    current_msg = global&.messages_count || unit_insights.sum(&:messages_count)
    previous_conv = prev_global&.conversations_count || prev_unit_insights.sum(&:conversations_count)

    {
      conversations: current_conv,
      messages: current_msg,
      conversations_delta_pct: pct_delta(previous_conv, current_conv),
      insights_analyzed: unit_insights.count,
      units_analyzed: unit_insights.map { |i| unit_key(i) }.uniq.count
    }
  end

  def build_unit_ranking(unit_insights, prev_unit_insights)
    entries = unit_insights.map { |i| unit_ranking_entry(i, prev_unit_insights) }
    entries.sort_by { |u| -u[:conversations] }
  end

  def unit_ranking_entry(insight, prev_unit_insights)
    prev = prev_unit_insights.find { |p| unit_key(p) == unit_key(insight) }
    {
      unit_id: unit_key(insight),
      unit_name: unit_name(insight),
      conversations: insight.conversations_count,
      messages: insight.messages_count,
      conversations_previous: prev&.conversations_count.to_i,
      conversations_delta_pct: pct_delta(prev&.conversations_count.to_i, insight.conversations_count)
    }
  end

  def build_ai_performance(unit_insights)
    per_unit = unit_insights.map { |i| ai_performance_entry(i) }
    per_unit.sort_by { |u| u[:success_rate_pct] || 100 } # piores primeiro
  end

  def ai_performance_entry(insight)
    failures_list = insight.payload&.dig('ai_failures') || []
    failures_count = failures_list.sum { |f| f['frequency'].to_i }
    total = insight.conversations_count.to_i
    success_rate = total.positive? ? ((total - failures_count).to_f / total * 100).round(1) : nil

    {
      unit_id: unit_key(insight),
      unit_name: unit_name(insight),
      conversations: total,
      failures_count: failures_count,
      success_rate_pct: success_rate,
      top_failures: failures_list.first(3)
    }
  end

  def build_satisfaction(unit_insights)
    per_unit = unit_insights.map { |i| satisfaction_entry(i) }
    {
      most_dissatisfied: per_unit.sort_by { |u| -u[:complaints_count] }.first(5),
      most_satisfied: per_unit.sort_by { |u| -u[:praises_count] }.first(5)
    }
  end

  def satisfaction_entry(insight)
    complaints = insight.payload&.dig('highlights', 'complaints') || []
    praises = insight.payload&.dig('highlights', 'praises') || []
    neg_pct, pos_pct = sentiment_percentages(insight.payload&.dig('sentiment') || {})

    {
      unit_id: unit_key(insight),
      unit_name: unit_name(insight),
      complaints_count: complaints.size,
      praises_count: praises.size,
      negative_pct: neg_pct,
      positive_pct: pos_pct,
      top_complaints: complaints.first(3),
      top_praises: praises.first(3)
    }
  end

  def sentiment_percentages(sentiment)
    negative = sentiment['negative_count'].to_i
    positive = sentiment['positive_count'].to_i
    total = negative + positive + sentiment['neutral_count'].to_i
    return [0, 0] unless total.positive?

    [(negative.to_f / total * 100).round(1), (positive.to_f / total * 100).round(1)]
  end

  def aggregate_top_items(insights, payload_key, label_key, count_key, limit:)
    all_items = insights.flat_map { |i| i.payload&.dig(payload_key) || [] }
    grouped = all_items.group_by { |item| item[label_key].to_s.downcase.strip }
    grouped.values
           .map { |items| items.first.merge(count_key => items.sum { |i| i[count_key].to_i }) }
           .sort_by { |item| -item[count_key].to_i }
           .first(limit)
  end

  def aggregate_text_highlights(insights, kind, limit:)
    all = insights.flat_map { |i| i.payload&.dig('highlights', kind) || [] }
    grouped = all.group_by { |s| s.to_s.downcase.strip }
    grouped.values
           .sort_by { |v| -v.size }
           .first(limit)
           .map { |v| { text: v.first, frequency: v.size } }
  end

  def aggregate_recommendations(insights, limit:)
    insights.flat_map { |i| i.payload&.dig('recommendations') || [] }
            .uniq
            .first(limit)
  end

  def build_period_summaries(unit_insights)
    unit_insights.filter_map { |i| summary_entry(i) }
  end

  def summary_entry(insight)
    summary = insight.payload&.dig('period_summary').to_s
    return nil if summary.blank?

    { unit_name: unit_name(insight), summary: summary }
  end

  def unit_key(insight)
    insight.inbox_id.present? ? "inbox:#{insight.inbox_id}" : "unit:#{insight.captain_unit_id}"
  end

  def unit_name(insight)
    if insight.inbox_id.present?
      insight.inbox&.name || "Canal ##{insight.inbox_id}"
    else
      insight.captain_unit&.name || "Unidade ##{insight.captain_unit_id}"
    end
  end

  def pct_delta(previous, current)
    return nil if previous.to_i.zero?

    ((current - previous).to_f / previous * 100).round(1)
  end

  def empty_digest
    {
      account_id: @account.id,
      account_name: @account.name,
      period_start: @period_start,
      period_end: @period_end,
      empty: true,
      totals: { conversations: 0, messages: 0, insights_analyzed: 0, units_analyzed: 0 },
      unit_ranking: [],
      ai_performance: [],
      satisfaction: { most_dissatisfied: [], most_satisfied: [] },
      top_topics: [],
      customer_opportunities: [],
      faq_gaps: [],
      complaints: [],
      praises: [],
      most_requested_suites: [],
      recommendations: [],
      period_summaries: []
    }
  end
end
# rubocop:enable Metrics/ClassLength
