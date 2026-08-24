class V2::Reports::Sinal::OverviewBuilder < V2::Reports::Sinal::BaseBuilder
  def build
    {
      kpis: kpis,
      series: series,
      ia: ia_metrics,
      topics: insight_topics,
      labels: labels_cloud,
      visual: V2::Reports::Sinal::VisualBuilder.new(account, params).build
    }
  end

  private

  def kpis
    received = messages_scope.where(created_at: range, message_type: :incoming).count
    prev_received = messages_scope.where(created_at: previous_range, message_type: :incoming).count
    {
      received: received,
      sent: messages_scope.where(created_at: range, message_type: :outgoing).count,
      audios: audio_count,
      prev_received: prev_received,
      pct_change: pct_change(received, prev_received)
    }
  end

  def audio_count
    scope = Attachment.joins(:message)
                      .where(account_id: account.id, file_type: :audio)
                      .where(messages: { message_type: :incoming, private: false, created_at: range })
    scope = scope.where(messages: { inbox_id: inbox_id }) if inbox_id
    scope.count
  end

  def pct_change(current, previous)
    return 0 if previous.zero?

    (((current - previous) / previous.to_f) * 100).round
  end

  # Série diária alinhada: dia N do período atual pareado com o dia N do anterior.
  def series
    current_counts = daily_counts(range)
    previous_counts = daily_counts(previous_range)
    previous_days = previous_counts.keys.sort

    current_counts.keys.sort.each_with_index.map do |day, index|
      {
        day: day.to_s,
        current: current_counts[day],
        previous: previous_days[index] ? previous_counts[previous_days[index]] : 0
      }
    end
  end

  def daily_counts(time_range)
    messages_scope.where(created_at: time_range)
                  .group_by_day(:created_at, time_zone: timezone, range: time_range)
                  .count
  end
end
