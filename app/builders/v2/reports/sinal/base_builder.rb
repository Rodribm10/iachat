# Base dos relatórios "Sinal nativo": réplicas das páginas do app Sinal
# alimentadas pelos dados do próprio Chatwoot (ver docs/specs/relatorios-sinal/CATALOGO.md).
class V2::Reports::Sinal::BaseBuilder
  include DateRangeHelper

  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  private

  def inbox_id
    params[:inbox_id].presence&.to_i
  end

  def timezone
    offset = params[:timezone_offset].to_f
    ActiveSupport::TimeZone[offset]&.name || 'UTC'
  end

  # Mensagens "de verdade": sem notas internas e sem activity.
  # Message tem default_scope de ordenação — unscope obrigatório em agregação.
  def messages_scope
    scope = account.messages.unscope(:order)
                   .where(private: false)
                   .where.not(message_type: :activity)
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope
  end

  def conversations_scope
    scope = account.conversations
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope
  end

  def reporting_events_scope(name)
    scope = account.reporting_events.where(name: name, created_at: range)
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope
  end

  def previous_range
    since_time = parse_date_time(params[:since]).to_time
    until_time = parse_date_time(params[:until]).to_time
    span = until_time - since_time
    (since_time - span)...since_time
  end

  def days_in_range
    since_time = parse_date_time(params[:since]).to_time
    until_time = parse_date_time(params[:until]).to_time
    [((until_time - since_time) / 1.day).round, 1].max
  end

  def ia_metrics
    {
      ai_messages: messages_scope.where(created_at: range, sender_type: 'Captain::Assistant').count,
      reservations_created: reservations_created_count,
      pix_paid: pix_paid_count,
      handoffs: reporting_events_scope(:conversation_bot_handoff).count,
      auto_closures: reporting_events_scope(:conversation_bot_resolved).count,
      human_requests: label_taggings_scope.where(tags: { name: 'triagem_humana' }).count
    }
  end

  def reservations_created_count
    scope = account.captain_reservations.where(created_at: range)
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope.where.not(status: :draft).count
  rescue StandardError
    0
  end

  def pix_paid_count
    scope = Captain::PixCharge.joins(:reservation)
                              .where(captain_reservations: { account_id: account.id })
                              .where(status: 'paid', paid_at: range)
    scope = scope.where(captain_reservations: { inbox_id: inbox_id }) if inbox_id
    scope.count
  rescue StandardError
    0
  end

  def label_taggings_scope
    scope = ActsAsTaggableOn::Tagging
            .joins('INNER JOIN conversations ON taggings.taggable_id = conversations.id')
            .joins('INNER JOIN tags ON taggings.tag_id = tags.id')
            .where(taggable_type: 'Conversation', context: 'labels')
            .where(conversations: { account_id: account.id, created_at: range })
    scope = scope.where(conversations: { inbox_id: inbox_id }) if inbox_id
    scope
  end

  def labels_cloud
    counts = label_taggings_scope.group('tags.name').count
    colors = account.labels.pluck(:title, :color).to_h
    rows = counts.filter_map do |name, count|
      next unless colors.key?(name)

      { topic: name, count: count, color: colors[name] }
    end
    rows.sort_by { |row| -row[:count] }.first(14)
  end

  # Temas extraídos por IA (Captain::ConversationInsight) cujo período
  # intersecta o range pedido, somados por tópico.
  # rubocop:disable Metrics/AbcSize
  def insight_topics(limit = 12)
    since_date = parse_date_time(params[:since]).to_date
    until_date = parse_date_time(params[:until]).to_date
    scope = Captain::ConversationInsight.where(account_id: account.id, status: 'done')
                                        .where('period_start <= ? AND period_end >= ?', until_date, since_date)
    scope = scope.where(inbox_id: inbox_id) if inbox_id

    totals = Hash.new(0)
    scope.pluck(:payload).each do |payload|
      (payload || {}).fetch('top_topics', []).each do |topic|
        next if topic['topic'].blank?

        totals[topic['topic']] += topic['count'].to_i
      end
    end
    totals.map { |topic, count| { topic: topic, count: count } }
          .sort_by { |row| -row[:count] }
          .first(limit)
  rescue StandardError
    []
  end
  # rubocop:enable Metrics/AbcSize
end
