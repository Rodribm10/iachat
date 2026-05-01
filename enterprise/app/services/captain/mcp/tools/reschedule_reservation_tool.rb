# Tool MCP: remarca uma reserva existente.
#
# Caso de uso: cliente diz "vou precisar mudar pra outra data", "queria
# adiantar pra sex", "consegue empurrar pra 25?". Tool ajusta o
# check_in_at/check_out_at da Captain::Reservation mais recente da
# conversa, mantendo categoria e total_amount intactos.
#
# Política Dolce Amore: remarcação tem que ser feita com no mínimo 3h
# de antecedência em relação ao check-in atual. Tool valida.
#
# Idempotente em datas iguais: se a nova data == atual, não toca em nada.
#
# Não cobre: mudança de categoria/preço (use cancel + generate_pix novo)
# ou cancelamento (transferir pra humano via frase-âncora).
class Captain::Mcp::Tools::RescheduleReservationTool < Captain::Mcp::Tools::BaseTool
  MIN_NOTICE_HOURS = 3

  class << self
    def name
      'reschedule_reservation'
    end

    def description
      'Remarca a reserva existente da conversa pra uma nova data. Mantém categoria e ' \
        'valor. Política: precisa ser pedido com no mínimo 3h de antecedência em relação ' \
        'ao check-in atual. Use quando cliente pedir mudança de data SEM mudar categoria. ' \
        'Pra mudança de categoria, transfira pra humano (frase-âncora).'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid do [ctx]). Obrigatório.'
          },
          new_check_in_date: {
            type: 'string',
            description: 'Nova data de check-in (YYYY-MM-DD ou DD/MM/YYYY). Hora padrão = mesma da reserva original.'
          },
          new_check_in_time: {
            type: 'string',
            description: 'Opcional. Nova hora de check-in (HH:MM, 24h). Default: mantém hora atual.'
          }
        },
        required: %w[conversation_id new_check_in_date]
      }
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def call(args, context:)
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]).') if conversation.blank?

    reservation = recent_reservation(conversation)
    return error_response('Não há reserva ativa pra remarcar nessa conversa.') if reservation.blank?

    new_check_in = build_new_check_in(args, reservation)
    return error_response('Não consegui interpretar a data. Use YYYY-MM-DD ou DD/MM/YYYY.') if new_check_in.blank?

    if new_check_in == reservation.check_in_at
      formatted = new_check_in.strftime('%d/%m/%Y %Hh%M')
      return text_response("Reserva ##{reservation.id} já está marcada pra #{formatted}. Nada a alterar.")
    end

    notice_hours = ((reservation.check_in_at - Time.current) / 1.hour).round
    if notice_hours < MIN_NOTICE_HOURS
      return error_response(
        "Política do hotel: remarcação precisa ser pedida com no mínimo #{MIN_NOTICE_HOURS}h de antecedência. " \
        "Faltam só #{notice_hours}h pro check-in atual — peça pro cliente confirmar com a gerência."
      )
    end

    duration = reservation.check_out_at - reservation.check_in_at
    reservation.update!(check_in_at: new_check_in, check_out_at: new_check_in + duration)
    post_reschedule_note(conversation, reservation, new_check_in)

    formatted = new_check_in.strftime('%d/%m/%Y às %Hh%M')
    valor = format('%.2f', reservation.total_amount.to_f)
    text_response(
      "Reserva ##{reservation.id} remarcada pra #{formatted} " \
      "(categoria #{reservation.suite_identifier}, valor R$ #{valor} mantido)."
    )
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::RescheduleReservationTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao remarcar: #{e.message}")
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  # Pega reserva mais recente da conversa que ainda não foi finalizada/cancelada.
  def recent_reservation(conversation)
    Captain::Reservation
      .where(conversation_id: conversation.id)
      .where.not(status: %w[cancelled done])
      .order(check_in_at: :desc)
      .first
  end

  def build_new_check_in(args, reservation) # rubocop:disable Metrics/AbcSize
    date = parse_date(args['new_check_in_date'])
    return nil if date.blank?

    time = parse_time(args['new_check_in_time']) || [reservation.check_in_at.hour, reservation.check_in_at.min]
    tz = reservation.account.respond_to?(:timezone) ? (reservation.account.timezone.presence || Time.zone.name) : Time.zone.name
    Time.use_zone(tz) { Time.zone.local(date.year, date.month, date.day, time[0], time[1], 0) }
  end

  def parse_date(raw)
    raw = raw.to_s.strip
    return nil if raw.blank?

    Date.iso8601(raw)
  rescue ArgumentError
    begin
      Date.strptime(raw, '%d/%m/%Y')
    rescue ArgumentError
      nil
    end
  end

  def parse_time(raw)
    raw = raw.to_s.strip
    return nil if raw.blank?

    match = raw.match(/\A(\d{1,2}):(\d{2})\z/)
    return nil unless match

    [match[1].to_i, match[2].to_i]
  end

  def post_reschedule_note(conversation, reservation, new_check_in)
    body = "🔄 Reserva ##{reservation.id} remarcada pra #{new_check_in.strftime('%d/%m/%Y às %Hh%M')}. Categoria e valor mantidos."
    Messages::MessageBuilder.new(
      nil,
      conversation,
      content: body,
      message_type: 'outgoing',
      private: true # nota interna pro time, cliente não vê
    ).perform
  rescue StandardError => e
    Rails.logger.warn("[Captain::Mcp::RescheduleReservationTool] failed to post note: #{e.class} - #{e.message}")
  end
end
