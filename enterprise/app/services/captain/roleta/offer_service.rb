# frozen_string_literal: true

# Lógica central da oferta de Roleta da Sorte.
# Reutilizada por (a) GenerateRoletaLinkTool — invocação manual pela Jasmine,
# e (b) Captain::Payments::OfferRouletteJob — disparado após confirmação do Pix.
# rubocop:disable Metrics/MethodLength,Metrics/AbcSize
class Captain::Roleta::OfferService
  DEFAULT_BASE_URL = 'http://localhost:5180'
  DEFAULT_SCHEMA = 'reserva_hotel'

  def initialize(reservation:)
    @reservation = reservation
  end

  # Cria (ou recupera) o draw e envia a mensagem de oferta pra conversa.
  # Retorna { success: bool, url: String?, error: String? }
  def perform
    conversation = @reservation.conversation
    return error('Reserva sem conversa.') if conversation.blank?

    assistant = conversation.inbox&.captain_assistant
    return error('Inbox sem assistente.') if assistant.blank?

    unit_row = fetch_unidade_for_conversation(conversation)
    return error('Sem unidade vinculada — tenant não resolvido.') if unit_row.blank?

    draw = create_or_get_draw(
      tenant_id: unit_row['tenant_id'],
      id_marca: unit_row['id_marca'],
      reservation_id: @reservation.id,
      contact_phone: conversation.contact&.phone_number,
      contact_name: conversation.contact&.name
    )
    return error('Falha ao criar draw.') if draw.blank?

    url = "#{base_url}/roleta/#{draw['token']}"
    dispatch_offer_message(assistant, conversation, url) if draw['was_created']
    { success: true, url: url, was_created: draw['was_created'] }
  rescue StandardError => e
    Rails.logger.error("[Roleta::OfferService] falha reserva=#{@reservation&.id}: #{e.class} - #{e.message}")
    error(e.message)
  end

  private

  def error(msg)
    { success: false, error: msg }
  end

  def fetch_unidade_for_conversation(conversation)
    unit = conversation&.inbox&.captain_inbox&.captain_unit
    return nil if unit.blank?

    supabase_get('unidades', { chatwoot_unit_id: "eq.#{unit.id}", select: '*', limit: 1 }).first
  end

  def create_or_get_draw(tenant_id:, id_marca:, reservation_id:, contact_phone:, contact_name:)
    body = {
      p_tenant_id: tenant_id,
      p_id_marca: id_marca,
      p_reservation_id: reservation_id,
      p_contact_phone: contact_phone,
      p_contact_name: contact_name
    }
    Array(supabase_rpc('create_or_get_draw', body)).first
  end

  def dispatch_offer_message(assistant, conversation, url)
    content = <<~MSG.strip
      Seu Pix foi confirmado! 💛

      Como prometido, agora é hora da sua chance na Roleta da Sorte 🎁 — você pode ganhar um brinde na recepção ou um desconto no saldo do check-in.

      É só clicar e girar:
      #{url}

      Um giro só. Boa sorte! 🍀
    MSG

    Messages::MessageBuilder.new(assistant, conversation, {
                                   content: content,
                                   message_type: 'outgoing'
                                 }).perform
  rescue StandardError => e
    Rails.logger.warn("[Roleta::OfferService] falha ao enviar msg reserva=#{@reservation&.id}: #{e.class} - #{e.message}")
  end

  def supabase_get(table, query)
    url = "#{supabase_url}/rest/v1/#{table}"
    response = supabase_client.get(url, query) do |req|
      req.headers['apikey'] = supabase_key
      req.headers['Authorization'] = "Bearer #{supabase_key}"
      req.headers['Accept-Profile'] = supabase_schema
      req.headers['Accept'] = 'application/json'
      req.headers['Accept-Encoding'] = 'identity'
    end
    return [] unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError
    []
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

  def base_url
    ENV.fetch('RESERVA_1001_BASE_URL', DEFAULT_BASE_URL).chomp('/')
  end
end
# rubocop:enable Metrics/MethodLength,Metrics/AbcSize
