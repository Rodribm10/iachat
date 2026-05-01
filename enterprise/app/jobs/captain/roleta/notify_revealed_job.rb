# frozen_string_literal: true

# Chamado após o cliente girar a roleta e o prêmio ser revelado.
# Claim atômico no Supabase garante que só UMA execução manda a mensagem,
# mesmo se o frontend dispara + um cron polling dispara simultâneo.
# rubocop:disable Metrics/MethodLength
class Captain::Roleta::NotifyRevealedJob < ApplicationJob
  DEFAULT_SCHEMA = 'reserva_hotel'

  queue_as :low

  def perform(token)
    return if token.blank?

    row = claim_draw(token)
    return if row.blank? # já notificado ou ainda pending

    reservation = Captain::Reservation.find_by(id: row['reservation_id'])
    return if reservation.blank?

    conversation = reservation.conversation
    return if conversation.blank?

    assistant = conversation.inbox&.captain_assistant
    return if assistant.blank?

    content = build_message(row)
    return if content.blank?

    Messages::MessageBuilder.new(assistant, conversation, {
                                   content: content,
                                   message_type: 'outgoing'
                                 }).perform

    Rails.logger.info(
      "[NotifyRevealedJob] token=#{token} reserva=#{reservation.id} premio=#{row['prize_nome']}"
    )
  end

  private

  def claim_draw(token)
    Array(supabase_rpc('claim_draw_for_notification', { p_token: token })).first
  end

  def build_message(row)
    case row['prize_tipo']
    when 'desconto_percentual'
      valor = Integer(Float(row['prize_valor']))
      <<~MSG.strip
        🎉 A roleta parou! Você ganhou #{valor}% de desconto no saldo do check-in 💛

        Mostra esse código na recepção:
        *#{row['code']}*

        Te espero por lá! 🍀
      MSG
    when 'brinde_fisico'
      <<~MSG.strip
        🎉 A roleta parou! Você ganhou: *#{row['prize_nome']}* 🎁

        Mostra esse código na recepção pra retirar seu brinde:
        *#{row['code']}*

        Te espero por lá! 🍀
      MSG
    else
      <<~MSG.strip
        Dessa vez a roleta não rolou pra você 🫶 — mas sua reserva tá garantida e eu te espero de braços abertos.

        Da próxima que voltar, tem roleta nova te esperando! 🍀
      MSG
    end
  end

  def supabase_rpc(fn_name, body)
    url = "#{supabase_url}/rest/v1/rpc/#{fn_name}"
    response = supabase_client.post(url) do |req|
      req.headers['apikey'] = supabase_key
      req.headers['Authorization'] = "Bearer #{supabase_key}"
      req.headers['Content-Profile'] = supabase_schema
      req.headers['Content-Type'] = 'application/json'
      req.headers['Accept'] = 'application/json'
      req.headers['Accept-Encoding'] = 'identity'
      req.body = body.to_json
    end
    return [] unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError
    []
  end

  def supabase_client
    @supabase_client ||= Faraday.new do |f|
      f.adapter Faraday.default_adapter
      f.options.timeout = 8
      f.options.open_timeout = 4
    end
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
# rubocop:enable Metrics/MethodLength
