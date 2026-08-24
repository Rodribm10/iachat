# "Panorama visual" da Overview (portado da branch codex/sinal-relatorios-visuais
# do Sinal): modelo de atendimento (só IA / misto / só humano), participantes,
# janelas de horário, formatos, adoção do sistema (painel x WhatsApp direto)
# e visão mensal — tudo do banco do Chatwoot.
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
      system_adoption: system_adoption,
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

  # "Humano" é a união de quem respondeu pelo painel (sender_type = User) com
  # quem respondeu direto no WhatsApp: resposta direta é sempre humana, então
  # entra na mesma fatia — ver whatsapp_direct_messages para o critério.
  def human_conversation_ids
    @human_conversation_ids ||= panel_human_messages.distinct.pluck(:conversation_id).to_set |
                                whatsapp_direct_messages.distinct.pluck(:conversation_id).to_set
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

  # ----- adoção do sistema: quanto do atendimento humano sai do painel -----

  # Resposta pelo painel de verdade: outgoing com sender_type = User.
  def panel_human_messages
    @panel_human_messages ||= range_messages.where(message_type: :outgoing, sender_type: 'User')
  end

  # Outgoing sem sender_type (mensagem sem autor) só conta como resposta
  # direta no WhatsApp quando tem source_id — é o eco real devolvido pelo
  # provider (gowa), prova de que a mensagem saiu de fato pelo app do
  # celular. Sem source_id não dá pra distinguir de lixo sem autor.
  def whatsapp_direct_messages
    @whatsapp_direct_messages ||= range_messages.where(message_type: :outgoing, sender_type: nil)
                                                .where.not(source_id: nil)
  end

  def system_adoption
    {
      panel: panel_human_messages.count,
      whatsapp_direct: whatsapp_direct_messages.count,
      heatmap: adoption_heatmap
    }
  end

  # Matriz dia da semana (0domingo..6sábado, convenção EXTRACT(dow) do
  # Postgres — mesma ordem que Date#wday em Ruby e Date#getDay em JS) x hora
  # do dia (0-23), com as duas contagens em cada célula. Não calcula
  # percentual aqui: uma célula sem nenhuma resposta (0 e 0) tem que chegar
  # diferenciável de uma célula com 0% de adoção real (0 e N) — quem decide
  # o que pinta "sem dado" é o front.
  def adoption_heatmap
    panel = dow_hour_counts(panel_human_messages)
    whatsapp = dow_hour_counts(whatsapp_direct_messages)
    (0..6).flat_map do |dow|
      (0..23).map do |hour|
        key = [dow, hour]
        { dow: dow, hour: hour, panel: panel[key] || 0, whatsapp_direct: whatsapp[key] || 0 }
      end
    end
  end

  def dow_hour_counts(scope)
    counts = scope.group(Arel.sql("EXTRACT(dow FROM #{local_time_sql})"), Arel.sql("EXTRACT(hour FROM #{local_time_sql})")).count
    counts.transform_keys { |(dow, hour)| [dow.to_i, hour.to_i] }
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

  # Postgres não conhece o fuso do Rails direto — SQL cru com AT TIME ZONE
  # precisa converter UTC (como created_at é salvo) pro identificador IANA.
  def local_time_sql
    "(messages.created_at AT TIME ZONE 'UTC' AT TIME ZONE #{ActiveRecord::Base.connection.quote(timezone_identifier)})"
  end

  def inbound_windows
    bucket = <<~SQL.squish
      CASE
        WHEN EXTRACT(dow FROM #{local_time_sql}) IN (0, 6) THEN 'weekend'
        WHEN EXTRACT(hour FROM #{local_time_sql}) >= 8 AND EXTRACT(hour FROM #{local_time_sql}) < 20 THEN 'commercial'
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
