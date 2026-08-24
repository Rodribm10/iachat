# Réplica da página "Mídia" do Sinal: inventário de anexos da conta inteira
# (sem filtro de período, como no original). Tipos vêm de attachments.file_type;
# sticker é content_type de messages, contado à parte.
class V2::Reports::Sinal::MediaBuilder < V2::Reports::Sinal::BaseBuilder
  TYPES = %w[audio image video file].freeze
  DRILL_LIMIT = 200
  BREAKDOWN_LIMIT = 50
  BUCKETS = { 'day' => 60, 'week' => 26, 'month' => 24 }.freeze

  def summary
    stats = TYPES.index_with { |type| type_stats(type) }
    stats['sticker'] = sticker_stats
    {
      by_type: stats.transform_values { |row| row[:total] },
      stats: stats,
      range: date_range
    }
  end

  # rubocop:disable Metrics/AbcSize
  def timeseries
    granularity = BUCKETS.key?(params[:granularity]) ? params[:granularity] : 'day'
    window = window_for(granularity)
    buckets = Hash.new { |hash, key| hash[key] = Hash.new(0) }

    TYPES.each do |type|
      scope = attachments_scope.where(file_type: type, messages: { created_at: window })
      grouped_counts(scope, 'messages.created_at', granularity).each do |bucket, count|
        buckets[bucket][type] = count
      end
    end
    grouped_counts(sticker_messages.where(created_at: window), :created_at, granularity).each do |bucket, count|
      buckets[bucket]['sticker'] = count
    end

    buckets.sort.map { |bucket, values| { bucket: bucket.to_s, values: values } }
  end

  def breakdown
    group_type = params[:scope] == 'group' ? :group : :individual
    scope = attachments_scope
            .joins(message: { conversation: :contact })
            .where(conversations: { group_type: group_type })
            .group('contacts.id', 'contacts.name', 'contacts.phone_number', 'attachments.file_type')
            .count

    rows = Hash.new { |hash, key| hash[key] = { total: 0, types: Hash.new(0) } }
    scope.each do |(contact_id, name, phone, file_type), count|
      row = rows[contact_id]
      row[:name] ||= name.presence || phone
      row[:types][file_type] += count
      row[:total] += count
    end
    rows.values.sort_by { |row| -row[:total] }.first(BREAKDOWN_LIMIT)
  end
  # rubocop:enable Metrics/AbcSize

  def messages
    scope = if params[:type] == 'sticker'
              sticker_messages
            else
              base = attachments_scope.joins(message: { conversation: :contact })
              base = base.where(file_type: params[:type]) if TYPES.include?(params[:type])
              base
            end
    scope = scope.where(messages: { message_type: direction }) if direction
    scope = if params[:type] == 'sticker'
              scope.preload(conversation: :contact)
            else
              scope.preload(message: { conversation: :contact })
            end
    scope.order('messages.created_at DESC').limit(DRILL_LIMIT).map { |record| drill_row(record) }
  end

  private

  def attachments_scope
    scope = Attachment.joins(:message)
                      .where(account_id: account.id)
                      .where(messages: { private: false, message_type: %i[incoming outgoing] })
    scope = scope.where(messages: { inbox_id: inbox_id }) if inbox_id
    scope = scope.where(messages: { created_at: range }) if range
    scope
  end

  def sticker_messages
    scope = account.messages.unscope(:order)
                   .joins(conversation: :contact)
                   .where(private: false, content_type: :sticker, message_type: %i[incoming outgoing])
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope = scope.where(created_at: range) if range
    scope
  end

  def type_stats(type)
    scope = attachments_scope.where(file_type: type)
    by_direction = scope.group('messages.message_type').count
    by_group = scope.joins(message: :conversation).group('conversations.group_type').count
    build_stats(scope.count, by_direction, by_group)
  end

  def sticker_stats
    scope = sticker_messages
    by_direction = scope.group(:message_type).count
    by_group = scope.group('conversations.group_type').count
    build_stats(scope.count, by_direction, by_group)
  end

  def build_stats(total, by_direction, by_group)
    {
      total: total,
      incoming: by_direction['incoming'] || by_direction[0] || 0,
      outgoing: by_direction['outgoing'] || by_direction[1] || 0,
      individual: by_group['individual'] || by_group[0] || 0,
      group: by_group['group'] || by_group[1] || 0
    }
  end

  # Com since/until explícitos (picker de período), a janela do gráfico segue
  # o período escolhido. Sem eles, mantém a janela fixa por granularidade
  # (comportamento padrão de quando a página carrega sem filtro).
  def window_for(granularity)
    return range if range

    case granularity
    when 'week' then BUCKETS['week'].weeks.ago..Time.current
    when 'month' then BUCKETS['month'].months.ago..Time.current
    else BUCKETS['day'].days.ago..Time.current
    end
  end

  def grouped_counts(scope, column, granularity)
    case granularity
    when 'week' then scope.group_by_week(column, time_zone: timezone).count
    when 'month' then scope.group_by_month(column, time_zone: timezone).count
    else scope.group_by_day(column, time_zone: timezone).count
    end.transform_keys(&:to_date)
  end

  def date_range
    first = attachments_scope.minimum('messages.created_at')
    last = attachments_scope.maximum('messages.created_at')
    { min_at: first, max_at: last }
  end

  def direction
    return :incoming if params[:direction] == 'incoming'
    return :outgoing if params[:direction] == 'outgoing'

    nil
  end

  def drill_row(record)
    message = record.is_a?(Attachment) ? record.message : record
    {
      id: message.id,
      file_type: record.is_a?(Attachment) ? record.file_type : 'sticker',
      direction: message.message_type,
      content: message.content.to_s.truncate(180),
      contact_name: message.conversation&.contact&.name.presence || message.conversation&.contact&.phone_number,
      conversation_id: message.conversation&.display_id,
      inbox_id: message.inbox_id,
      created_at: message.created_at
    }
  end
end
