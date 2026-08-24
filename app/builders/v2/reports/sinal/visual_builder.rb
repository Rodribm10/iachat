# "Panorama visual" da Overview (portado da branch codex/sinal-relatorios-visuais
# do Sinal): modelo de atendimento (só IA / misto / só humano), participantes,
# janelas de horário, formatos e visão mensal — tudo do banco do Chatwoot.
class V2::Reports::Sinal::VisualBuilder < V2::Reports::Sinal::BaseBuilder
  MONTHS_WINDOW = 6

  def build
    {
      contacts: contact_ids.size,
      contacts_ai_attended: (contact_ids & ai_contact_ids).size,
      new_contacts: new_contact_ids.size,
      new_contacts_ai_attended: (new_contact_ids & ai_contact_ids).size,
      participants: participants,
      inbound_windows: inbound_windows,
      formats: formats,
      service_modes: service_modes,
      months: months
    }
  end

  private

  def range_messages
    messages_scope.where(created_at: range)
  end

  # ----- conversas por modo de atendimento -----

  def attended_conversation_ids
    @attended_conversation_ids ||= range_messages.where(message_type: :incoming)
                                                 .distinct.pluck(:conversation_id).to_set
  end

  def ai_conversation_ids
    @ai_conversation_ids ||= range_messages.where(message_type: :outgoing, sender_type: 'Captain::Assistant')
                                           .distinct.pluck(:conversation_id).to_set
  end

  def human_conversation_ids
    @human_conversation_ids ||= range_messages.where(message_type: :outgoing, sender_type: 'User')
                                              .distinct.pluck(:conversation_id).to_set
  end

  def service_modes
    base = attended_conversation_ids
    ai = ai_conversation_ids & base
    human = human_conversation_ids & base
    {
      ai_only: (ai - human).size,
      mixed: (ai & human).size,
      human_only: (human - ai).size,
      total: base.size,
      unclassified: (base - ai - human).size
    }
  end

  # ----- contatos -----

  def contact_ids
    @contact_ids ||= range_messages.where(message_type: :incoming)
                                   .joins(:conversation)
                                   .distinct.pluck('conversations.contact_id').compact.to_set
  end

  def ai_contact_ids
    @ai_contact_ids ||= range_messages.where(message_type: :outgoing, sender_type: 'Captain::Assistant')
                                      .joins(:conversation)
                                      .distinct.pluck('conversations.contact_id').compact.to_set
  end

  # Lead novo = primeira conversa do contato na conta caiu dentro do período
  # (mesma semântica do funil de conversão do fork).
  def new_contact_ids
    @new_contact_ids ||= conversations_scope
                         .where(created_at: range)
                         .where.not(contact_id: nil)
                         .where('NOT EXISTS (SELECT 1 FROM conversations prev
                                 WHERE prev.contact_id = conversations.contact_id
                                   AND prev.account_id = conversations.account_id
                                   AND prev.id < conversations.id)')
                         .distinct.pluck(:contact_id).to_set
  end

  # ----- mensagens -----

  def participants
    outgoing = range_messages.where(message_type: :outgoing).group(:sender_type).count
    {
      client: range_messages.where(message_type: :incoming).count,
      ai: outgoing['Captain::Assistant'] || 0,
      human: outgoing['User'] || 0,
      other: outgoing.except('Captain::Assistant', 'User').values.sum
    }
  end

  def inbound_windows
    local = "(messages.created_at AT TIME ZONE 'UTC' AT TIME ZONE #{ActiveRecord::Base.connection.quote(timezone_identifier)})"
    bucket = <<~SQL.squish
      CASE
        WHEN EXTRACT(dow FROM #{local}) IN (0, 6) THEN 'weekend'
        WHEN EXTRACT(hour FROM #{local}) >= 8 AND EXTRACT(hour FROM #{local}) < 20 THEN 'commercial'
        ELSE 'after_hours'
      END
    SQL
    counts = range_messages.where(message_type: :incoming).group(Arel.sql(bucket)).count
    {
      commercial: counts['commercial'] || 0,
      after_hours: counts['after_hours'] || 0,
      weekend: counts['weekend'] || 0
    }
  end

  def formats
    total = range_messages.where(message_type: %i[incoming outgoing]).count
    audio = with_attachment_count(['audio'])
    media = with_attachment_count(%w[image video file location fallback share contact])
    {
      text: [total - audio - media, 0].max,
      audio: audio,
      media: media
    }
  end

  def with_attachment_count(types)
    range_messages.where(message_type: %i[incoming outgoing])
                  .joins(:attachments)
                  .where(attachments: { file_type: types })
                  .distinct.count(:id)
  end

  # ----- visão mensal (janela fixa de 6 meses, independente do range) -----

  def months
    window = (MONTHS_WINDOW - 1).months.ago.beginning_of_month..Time.current
    received = monthly_counts(messages_scope.where(message_type: :incoming), window)
    ai = monthly_counts(messages_scope.where(message_type: :outgoing, sender_type: 'Captain::Assistant'), window)
    human = monthly_counts(messages_scope.where(message_type: :outgoing, sender_type: 'User'), window)

    received.keys.sort.map do |month|
      {
        month: month.strftime('%Y-%m'),
        received: received[month] || 0,
        ai: ai[month] || 0,
        human: human[month] || 0
      }
    end
  end

  def monthly_counts(scope, window)
    scope.where(created_at: window)
         .group_by_month(:created_at, time_zone: timezone, range: window)
         .count
  end
end
