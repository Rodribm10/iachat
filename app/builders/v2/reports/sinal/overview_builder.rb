class V2::Reports::Sinal::OverviewBuilder < V2::Reports::Sinal::BaseBuilder
  def build
    {
      kpis: kpis,
      waiting: waiting,
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

  # Quem esta esperando resposta AGORA — nao no periodo selecionado. E o unico
  # bloco da pagina que ignora o filtro de datas de proposito: fila e estado do
  # instante, e a pergunta que ele responde ("tem alguem pendurado?") so faz
  # sentido no presente.
  #
  # Deriva de `waiting_since` (coluna indexada que o Chatwoot zera sozinho em
  # toda resposta nao-privada e na resolucao). Nao existe etiqueta por tras:
  # etiqueta de estado precisa ser escrita E apagada, e o apagar sempre tem um
  # caminho que nao roda — foi assim que 166 `cliente_aguardando`/`demora_critica`
  # ficaram penduradas em conversas ja resolvidas. Consulta em tempo de leitura
  # nao tem esse problema: quem foi respondido some da conta no mesmo segundo.
  #
  # `by_owner` e a informacao que nao existia em lugar nenhum: separa quem espera
  # a IA (`pending`, o funil dela) de quem espera uma pessoa (`open`). Sem isso
  # nao da pra saber se o gargalo e a IA ou a equipe — e foi exatamente por isso
  # que a conv 55 da academia ficou horas parada sem ninguem perceber.
  WAITING_SOON_MINUTES = 30
  WAITING_LATE_MINUTES = 120

  def waiting
    rows = conversations_scope.where(status: %i[open pending])
                              .where.not(waiting_since: nil)
                              .pluck(:status, :waiting_since)
    now = Time.current
    minutes = rows.map { |_status, since| ((now - since) / 60).floor }

    {
      total: rows.size,
      oldest_minutes: minutes.max || 0,
      by_owner: {
        ai: rows.count { |status, _| status.to_s == 'pending' },
        human: rows.count { |status, _| status.to_s == 'open' }
      },
      buckets: {
        recent: minutes.count { |m| m < WAITING_SOON_MINUTES },
        soon: minutes.count { |m| m >= WAITING_SOON_MINUTES && m < WAITING_LATE_MINUTES },
        late: minutes.count { |m| m >= WAITING_LATE_MINUTES }
      }
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
