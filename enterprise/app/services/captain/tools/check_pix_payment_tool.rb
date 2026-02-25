# rubocop:disable Metrics/ClassLength
class Captain::Tools::CheckPixPaymentTool < Captain::Tools::BaseTool
  def name
    'check_pix_payment'
  end

  def description
    'Consulta o status de pagamento de um Pix no Banco Inter. ' \
      'Use quando o cliente informar que já pagou e você precisar confirmar no banco.'
  end

  def tool_parameters_schema
    {
      type: 'object',
      properties: {
        txid: {
          type: 'string',
          description: 'Opcional. TXID da cobrança Pix para consulta direta.'
        }
      }
    }
  end

  def execute(*args, **params)
    actual_params = setup_execution_context!(args, params)
    return error_response('Erro técnico ao consultar pagamento. Não foi possível identificar a conversa atual.') if @conversation.blank?

    process_payment_check(actual_params)
  rescue StandardError => e
    Rails.logger.error("[CheckPixPaymentTool] Falha ao consultar pagamento: #{e.class} - #{normalize_text(e.message)}")
    tool_feedback_response(map_error_message(e))
  end

  private

  def setup_execution_context!(args, params)
    actual_params = resolve_params(args, params)
    @conversation ||= resolve_conversation(args, params)
    actual_params
  end

  def process_payment_check(actual_params)
    charge = find_charge(actual_params[:txid])
    return not_found_response if charge.blank?
    return already_paid_response(charge) if charge.paid? || charge.reservation&.payment_status.to_s == 'paid'

    status_result = Captain::Inter::CobStatusService.new(charge).call
    return pending_response(status_result[:status]) unless status_result[:paid]

    mark_charge_as_paid!(charge, status_result)
    paid_response(charge, status_result)
  end

  def find_charge(txid_param)
    if txid_param.present?
      return Captain::PixCharge.joins(:reservation)
                               .where(txid: txid_param.to_s.strip)
                               .where(captain_reservations: { conversation_id: @conversation.id, account_id: @conversation.account_id })
                               .order(created_at: :desc)
                               .first
    end

    Captain::PixCharge.joins(:reservation)
                      .where(captain_reservations: { conversation_id: @conversation.id, account_id: @conversation.account_id })
                      .order(created_at: :desc)
                      .first
  end

  def mark_charge_as_paid!(charge, status_result)
    update_attrs = {
      status: 'paid',
      raw_webhook_payload: status_result[:raw_payload]
    }
    update_attrs[:e2eid] = status_result[:end_to_end_id] if charge.e2eid.blank? && status_result[:end_to_end_id].present?
    update_attrs[:paid_at] = Time.current if charge.paid_at.blank?

    charge.update!(update_attrs)

    reservation = charge.reservation
    return if reservation.blank?
    return if reservation.payment_status.to_s == 'paid'

    Captain::Payments::ConfirmationService.new(
      reservation: reservation,
      source: 'inter_cob_query',
      payload: status_result[:raw_payload]
    ).perform
  end

  def not_found_response
    tool_feedback_response(
      'Não encontrei uma cobrança Pix vinculada a esta conversa. ' \
      'Se quiser, posso gerar um novo Pix.'
    )
  end

  def already_paid_response(charge)
    reservation_id = charge.reservation_id
    tool_feedback_response(
      "Pagamento já confirmado para a reserva ##{reservation_id}. " \
      'Se precisar, posso seguir com os próximos passos da reserva.'
    )
  end

  def paid_response(charge, status_result)
    reservation_id = charge.reservation_id
    value = status_result[:paid_value].presence || charge.original_value
    tool_feedback_response(
      "Pagamento confirmado no Banco Inter para a reserva ##{reservation_id} " \
      "(TXID: #{charge.txid}, valor: R$ #{format('%.2f', value.to_f)})."
    )
  end

  def pending_response(inter_status)
    status_label = inter_status.presence || 'ATIVA'
    tool_feedback_response(
      "Ainda não apareceu como pago no Banco Inter (status: #{status_label}). " \
      'Pode levar alguns instantes. Se quiser, eu consulto novamente em seguida.'
    )
  end

  def error_response(msg)
    { formatted_message: msg, success: false }
  end

  def tool_feedback_response(msg)
    { formatted_message: msg, success: true }
  end

  def map_error_message(error)
    message = normalize_text(error.message).downcase
    if message.include?('login/senha inválido') || message.include?('login/senha invalido')
      return 'Não consegui validar o pagamento no Inter porque as credenciais da integração estão inválidas. ' \
             'Peça para o gestor revisar Client ID/Secret/certificados.'
    end
    if message.include?('unit not configured for pix')
      return 'Não consegui validar o pagamento porque a unidade da conversa não está configurada para Pix.'
    end

    'Não consegui validar o pagamento agora por instabilidade técnica. Tente novamente em instantes.'
  end

  def resolve_params(args, params)
    merged = params.to_h

    args.each do |arg|
      next unless arg.is_a?(Hash)
      next if tool_context_hash?(arg)

      merged = arg.merge(merged)
    end

    merged.with_indifferent_access
  end

  # rubocop:disable Metrics/CyclomaticComplexity
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
  # rubocop:enable Metrics/CyclomaticComplexity

  def extract_state(args, params)
    context_sources = [
      *args,
      params[:tool_context],
      params['tool_context'],
      params[:context_wrapper],
      params['context_wrapper'],
      params[:context],
      params['context']
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

  def tool_context_hash?(hash)
    hash.key?(:state) ||
      hash.key?('state') ||
      hash.key?(:context) ||
      hash.key?('context') ||
      hash.key?(:conversation) ||
      hash.key?('conversation')
  end

  def normalize_text(value)
    value.to_s
         .dup
         .force_encoding(Encoding::UTF_8)
         .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
  rescue StandardError
    value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
  end
end
# rubocop:enable Metrics/ClassLength
