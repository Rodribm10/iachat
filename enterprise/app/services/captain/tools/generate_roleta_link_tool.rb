# frozen_string_literal: true

# Tool manual pra oferecer a Roleta da Sorte. O caminho AUTOMÁTICO de disparo
# (após confirmação do Pix) passa por Captain::Payments::OfferRouletteJob.
# Esse tool fica disponível pra casos em que alguém queira forçar a oferta
# manualmente (ex: reserva paga antes do cron detectar, ação de gerência, etc).
class Captain::Tools::GenerateRoletaLinkTool < Captain::Tools::BaseTool
  def name
    'generate_roleta_link'
  end

  def description
    <<~DESC.strip
      Oferta manual da Roleta da Sorte pra reserva atual. Normalmente a roleta é enviada
      AUTOMATICAMENTE quando o pagamento do Pix é confirmado. Use este tool só se precisar
      forçar a oferta fora do fluxo normal (reserva já paga que nunca recebeu link).
      Idempotente: chamar 2x na mesma reserva retorna o mesmo link.
    DESC
  end

  def tool_parameters_schema
    { type: 'object', properties: {} }
  end

  def execute(*args, **params)
    conversation = resolve_conversation(args, params)
    return error_response('Não consegui identificar a conversa.') if conversation.blank?

    reservation = Captain::Reservation.where(conversation_id: conversation.id).order(created_at: :desc).first
    return error_response('Sem reserva vinculada a essa conversa.') if reservation.blank?

    result = Captain::Roleta::OfferService.new(reservation: reservation).perform
    return error_response(result[:error] || 'Falha ao gerar roleta.') unless result[:success]

    { formatted_message: result[:url], raw_payload: result[:url], success: true, was_created: result[:was_created] }
  rescue StandardError => e
    Rails.logger.error("[GenerateRoletaLinkTool] falha: #{e.class} - #{e.message}")
    error_response('Não consegui gerar o link da roleta agora.')
  end

  private

  def error_response(msg)
    { formatted_message: msg, success: false }
  end

  # Resolvers de conversa — copiado de GenerateReservationLinkTool
  def resolve_conversation(args, params)
    state = extract_state(args, params)
    return nil if state.blank?

    conversation_state = state_from_context_hash(state, :conversation) || {}
    conversation_id = state_from_context_hash(conversation_state, :id)
    display_id = state_from_context_hash(conversation_state, :display_id)
    account_id = state[:account_id] || state['account_id']

    conversation = Conversation.find_by(id: conversation_id) if conversation_id.present?
    return conversation if conversation.present?
    return nil if display_id.blank?

    scope = Conversation.where(display_id: display_id)
    scope = scope.where(account_id: account_id) if account_id.present?
    scope.first
  end

  def extract_state(args, params)
    context_sources = [
      *args,
      params[:tool_context], params['tool_context'],
      params[:context_wrapper], params['context_wrapper'],
      params[:context], params['context']
    ].compact

    context_sources.each do |source|
      state = extract_state_from_source(source)
      return state if state.present?
    end
    {}
  end

  def extract_state_from_source(source)
    return source.state if source.respond_to?(:state)
    return state_from_source_context(source) if source.respond_to?(:context)
    return state_from_hash_source(source) if source.is_a?(Hash)

    nil
  end

  def state_from_source_context(source)
    context = source.context
    return nil unless context.is_a?(Hash)

    state_from_context_hash(context, :state)
  end

  def state_from_hash_source(source)
    state_from_context_hash(source, :state) ||
      source.dig(:context, :state) ||
      source.dig('context', 'state')
  end

  def state_from_context_hash(hash, key)
    hash[key] || hash[key.to_s]
  end
end
