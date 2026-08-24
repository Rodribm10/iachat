# Réplica da página "Privado" do Sinal: inteligência das conversas individuais
# (grupos ficam de fora — group_type é coluna de primeira classe aqui).
class V2::Reports::Sinal::PrivadoBuilder < V2::Reports::Sinal::BaseBuilder
  UNANSWERED_LIMIT = 20

  def build
    {
      kpis: kpis,
      ia: ia_metrics,
      inboxes: inbox_comparison,
      topics: insight_topics(40),
      labels: labels_cloud,
      unanswered: unanswered_conversations
    }
  end

  private

  def individual_messages
    messages_scope.joins(:conversation).where(conversations: { group_type: :individual })
  end

  def individual_conversations
    conversations_scope.where(group_type: :individual)
  end

  # rubocop:disable Metrics/AbcSize
  def kpis
    received = individual_messages.where(created_at: range, message_type: :incoming).count
    prev_received = individual_messages.where(created_at: previous_range, message_type: :incoming).count
    reply_stats = reply_time_stats
    {
      received: received,
      avg_per_day: (received / days_in_range.to_f).round(1),
      pct_change: prev_received.zero? ? 0 : (((received - prev_received) / prev_received.to_f) * 100).round,
      sparkline: sparkline,
      response_avg_minutes: reply_stats[:avg],
      response_median_minutes: reply_stats[:median],
      response_samples: reply_stats[:samples],
      unattended_count: unanswered_scope.count,
      open_count: individual_conversations.open.count
    }
  end
  # rubocop:enable Metrics/AbcSize

  def sparkline
    individual_messages.where(created_at: range, message_type: :incoming)
                       .group_by_day(:created_at, time_zone: timezone, range: range)
                       .count.sort.map(&:last)
  end

  def reply_time_stats
    scope = reporting_events_scope(:reply_time)
    samples = scope.count
    return { avg: nil, median: nil, samples: 0 } if samples.zero?

    avg = scope.average(:value).to_f
    median = scope.pick(Arel.sql('percentile_cont(0.5) within group (order by value)')).to_f
    { avg: (avg / 60.0).round, median: (median / 60.0).round, samples: samples }
  end

  def unanswered_scope
    individual_conversations.open.where.not(waiting_since: nil)
  end

  # rubocop:disable Metrics/AbcSize
  def inbox_comparison
    inbound = individual_messages.where(created_at: range, message_type: :incoming)
                                 .group(:inbox_id).count
    conversations = individual_conversations.where(created_at: range).group(:inbox_id).count
    unattended = unanswered_scope.group(:inbox_id).count

    rows = account.inboxes.map do |inbox|
      {
        inbox_id: inbox.id,
        name: inbox.name,
        inbound: inbound[inbox.id] || 0,
        conversations: conversations[inbox.id] || 0,
        unanswered: unattended[inbox.id] || 0
      }
    end
    rows.reject { |row| row[:inbound].zero? && row[:conversations].zero? && row[:unanswered].zero? }
        .sort_by { |row| [-row[:unanswered], -row[:inbound]] }
  end
  # rubocop:enable Metrics/AbcSize

  def unanswered_conversations
    conversations = unanswered_scope.order(waiting_since: :asc)
                                    .limit(UNANSWERED_LIMIT)
                                    .includes(:contact, :inbox)
    last_texts = last_incoming_texts(conversations.map(&:id))

    conversations.map do |conversation|
      {
        conversation_id: conversation.display_id,
        inbox_id: conversation.inbox_id,
        inbox_name: conversation.inbox&.name,
        contact_name: conversation.contact&.name.presence || conversation.contact&.phone_number,
        last_text: last_texts[conversation.id],
        waiting_since: conversation.waiting_since
      }
    end
  end

  def last_incoming_texts(conversation_ids)
    return {} if conversation_ids.empty?

    Message.unscope(:order)
           .where(conversation_id: conversation_ids, message_type: :incoming, private: false)
           .where.not(content: nil)
           .order(:conversation_id, created_at: :desc)
           .select('DISTINCT ON (conversation_id) conversation_id, content')
           .to_h { |message| [message.conversation_id, message.content.to_s.truncate(140)] }
  end
end
