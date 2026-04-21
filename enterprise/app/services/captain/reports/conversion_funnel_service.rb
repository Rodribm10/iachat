# frozen_string_literal: true

# Funil de conversão 5-etapas: perguntou preço → recebeu preço →
# reserva iniciada → Pix gerado → Pix pago. Identifica drop-off.
class Captain::Reports::ConversionFunnelService
  DEFAULT_PERIOD_DAYS = 30
  MAX_PERIOD_DAYS = 180

  PRICE_QUESTION_RE = /(pre[çc]o|quanto\s+custa|valor\b|tabela|or[çc]amento|qual\s+o\s+pre)/i
  PRICE_ANSWER_RE   = /r\$\s*\d|\b\d{2,3}\s*reais\b|\bcus(ta|tam)\b.*\d/i

  SUITE_RE = /\b(alexa|stilo|est[íi]lo|hidro(massagem)?|banheira|jacuzzi|of[uú]r[óo])\b/i

  STAGES = [
    { key: 'price_inquiry',       label: 'Perguntou preço' },
    { key: 'price_answered',      label: 'Recebeu cotação' },
    { key: 'reservation_drafted', label: 'Reserva iniciada' },
    { key: 'pix_generated',       label: 'Pix gerado' },
    { key: 'pix_paid',            label: 'Pix pago' }
  ].freeze

  def initialize(account:, period_days: DEFAULT_PERIOD_DAYS)
    @account = account
    @period_days = [period_days.to_i, MAX_PERIOD_DAYS].min
    @period_days = DEFAULT_PERIOD_DAYS if @period_days <= 0
    @period_end = Time.current
    @period_start = @period_end - @period_days.days
  end

  def call
    conversations = scope_conversations
    return empty_report if conversations.empty?

    analyzed = conversations.map { |conv| analyze_conversation(conv) }
    funnel = build_funnel(analyzed)
    by_suite = build_by_suite(analyzed)

    {
      period_start: @period_start.iso8601,
      period_end: @period_end.iso8601,
      period_days: @period_days,
      total_conversations_analyzed: analyzed.size,
      funnel: funnel,
      by_suite: by_suite,
      top_drop_off: compute_top_drop_off(funnel)
    }
  rescue StandardError => e
    Rails.logger.error("[ConversionFunnelService] #{e.class}: #{e.message}")
    empty_report(error: e.message)
  end

  private

  def empty_report(error: nil)
    {
      period_start: @period_start.iso8601,
      period_end: @period_end.iso8601,
      period_days: @period_days,
      total_conversations_analyzed: 0,
      funnel: STAGES.map { |s| s.merge(count: 0, conversion: nil) },
      by_suite: {},
      top_drop_off: nil,
      error: error
    }.compact
  end

  # Conversas do período em que Captain::Assistant participou.
  def scope_conversations
    @account.conversations
            .joins(:messages)
            .where('conversations.created_at >= ? AND conversations.created_at <= ?', @period_start, @period_end)
            .where(messages: { sender_type: 'Captain::Assistant' })
            .distinct
            .includes(:messages)
  end

  # Para cada conversa, determina o MAX stage alcançado + a categoria mencionada.
  # rubocop:disable Metrics/AbcSize
  def analyze_conversation(conv)
    messages = conv.messages.where(private: false).order(:created_at).to_a
    incoming = messages.select { |m| m.message_type == 'incoming' }
    outgoing = messages.select { |m| m.message_type == 'outgoing' && m.sender_type == 'Captain::Assistant' }

    max_stage = nil
    max_stage = 'price_inquiry' if incoming.any? { |m| PRICE_QUESTION_RE.match?(m.content.to_s) }
    max_stage = 'price_answered' if max_stage && outgoing.any? { |m| PRICE_ANSWER_RE.match?(m.content.to_s) }

    reservation = Captain::Reservation.where(conversation_id: conv.id).order(created_at: :asc).first

    if reservation
      max_stage ||= 'reservation_drafted'
      max_stage = 'reservation_drafted' if STAGES.index { |s| s[:key] == max_stage } < 2
    end

    max_stage = 'pix_generated' if reservation && pix_charge?(reservation) && (STAGES.index { |s| s[:key] == max_stage }.to_i < 3)

    max_stage = 'pix_paid' if reservation && reservation.payment_status.to_s == 'paid'

    {
      conversation_id: conv.id,
      max_stage: max_stage,
      suite: detect_suite(messages)
    }
  end

  # rubocop:enable Metrics/AbcSize

  def pix_charge?(reservation)
    Captain::PixCharge.exists?(reservation_id: reservation.id)
  end

  def detect_suite(messages)
    messages.each do |m|
      next if m.content.blank?

      md = SUITE_RE.match(m.content)
      next unless md

      word = md[1].downcase
      return 'Alexa' if word == 'alexa'
      return 'Stilo' if %w[stilo estilo estílo].include?(word)
      return 'Hidromassagem' if %w[hidro hidromassagem banheira jacuzzi ofuro ofurô].include?(word)
    end
    nil
  end

  def build_funnel(analyzed)
    # Conta cumulativamente: quem chegou em "reservation_drafted" também conta em "price_answered" e "price_inquiry".
    stage_order = STAGES.pluck(:key)
    counts = Hash.new(0)
    analyzed.each do |row|
      max_index = stage_order.index(row[:max_stage])
      next unless max_index

      stage_order[0..max_index].each { |k| counts[k] += 1 }
    end

    previous = nil
    STAGES.map do |stage|
      count = counts[stage[:key]]
      conversion = previous&.positive? ? (count.to_f / previous).round(3) : nil
      previous = count
      stage.merge(count: count, conversion: conversion)
    end
  end

  def build_by_suite(analyzed)
    grouped = analyzed.group_by { |row| row[:suite] }.reject { |k, _| k.nil? }
    grouped.transform_values { |rows| build_funnel(rows).map { |s| s.slice(:key, :label, :count) } }
  end

  def compute_top_drop_off(funnel)
    drops = funnel.each_cons(2).filter_map do |from, to|
      next nil unless from[:count].positive?

      lost = from[:count] - to[:count]
      pct = lost.to_f / from[:count]
      { from: from[:key], to: to[:key], lost: lost, drop_pct: pct.round(3) }
    end

    return nil if drops.empty?

    drops.max_by { |d| d[:drop_pct] }
  end
end
