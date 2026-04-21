# frozen_string_literal: true

# Marca um cupom como resgatado na recepção. Chama RPC atômica no Supabase,
# envia msg automática de confirmação pro cliente via Jasmine.
# rubocop:disable Metrics/MethodLength,Metrics/AbcSize
class Captain::Roleta::RedeemService
  DEFAULT_SCHEMA = 'reserva_hotel'

  Result = Struct.new(:success, :error_code, :reservation_id, :prize_nome, :prize_tipo, :prize_valor,
                      :contact_phone, :contact_name, :redeemed_at, keyword_init: true)

  def initialize(code:, receptionist_user:, notes: nil)
    @code = code.to_s.strip.upcase
    @receptionist_user = receptionist_user
    @notes = notes
  end

  def perform
    return failure('empty_code') if @code.blank?
    return failure('no_receptionist') if @receptionist_user.blank?

    row = call_rpc
    return failure('rpc_failed') if row.blank?

    result = Result.new(
      success: row['ok'] == true || row['ok'] == 'true',
      error_code: row['error_code'],
      reservation_id: row['reservation_id'],
      prize_nome: row['prize_nome'],
      prize_tipo: row['prize_tipo'],
      prize_valor: row['prize_valor'],
      contact_phone: row['contact_phone'],
      contact_name: row['contact_name'],
      redeemed_at: row['redeemed_at']
    )

    dispatch_confirmation_message(result) if result.success

    result
  rescue StandardError => e
    Rails.logger.error("[Roleta::RedeemService] falha: #{e.class} - #{e.message}")
    failure('exception')
  end

  private

  def failure(code)
    Result.new(success: false, error_code: code)
  end

  def call_rpc
    body = {
      p_code: @code,
      p_receptionist_user_id: @receptionist_user.id,
      p_notes: @notes.presence
    }
    Array(supabase_rpc('mark_draw_redeemed', body)).first
  end

  def dispatch_confirmation_message(result)
    reservation = Captain::Reservation.find_by(id: result.reservation_id)
    return if reservation.blank?

    conversation = reservation.conversation
    return if conversation.blank?

    assistant = conversation.inbox&.captain_assistant
    return if assistant.blank?

    content = build_message(result)
    Messages::MessageBuilder.new(assistant, conversation, {
                                   content: content,
                                   message_type: 'outgoing'
                                 }).perform
  rescue StandardError => e
    Rails.logger.warn("[Roleta::RedeemService] falha ao mandar msg: #{e.class} - #{e.message}")
  end

  def build_message(result)
    prize_desc = case result.prize_tipo
                 when 'desconto_percentual'
                   "#{Integer(Float(result.prize_valor))}% de desconto"
                 else
                   result.prize_nome
                 end

    horario = Time.current.in_time_zone('America/Sao_Paulo').strftime('%Hh%M')

    <<~MSG.strip
      ✅ Seu prêmio *#{prize_desc}* foi entregue na recepção (#{horario}).

      Se por algum motivo você NÃO recebeu, me avisa aqui que a gente resolve na hora 🫶
    MSG
  end

  def supabase_rpc(fn_name, body)
    url = "#{supabase_url}/rest/v1/rpc/#{fn_name}"
    response = Faraday.post(url) do |req|
      req.headers['apikey'] = supabase_key
      req.headers['Authorization'] = "Bearer #{supabase_key}"
      req.headers['Content-Profile'] = supabase_schema
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept'] = 'application/json'
      req.body = body.to_json
    end
    return [] unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError
    []
  end

  def supabase_url
    ENV.fetch('RESERVA_1001_SUPABASE_URL').chomp('/')
  end

  def supabase_key
    ENV.fetch('RESERVA_1001_SUPABASE_ANON_KEY')
  end

  def supabase_schema
    ENV.fetch('RESERVA_1001_SUPABASE_SCHEMA', DEFAULT_SCHEMA)
  end
end
# rubocop:enable Metrics/MethodLength,Metrics/AbcSize
