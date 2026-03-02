# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize
# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Layout/LineLength
# rubocop:disable Rails/SkipsModelValidations
# This class was migrated from reference/ with intentional complexity in execute/verify methods.
# Refactoring is tracked as tech debt rather than done inline.
class Captain::Tools::CreateReservationIntentTool < Captain::Tools::BaseTool
  def name
    'create_reservation_intent'
  end

  def description
    'Cria uma reserva draft quando o cliente confirmar suíte, preço e horário de chegada. ' \
      'IMPORTANTE: Extraia o horário EXATO de chegada da conversa e passe em check_in_at. ' \
      'Se o cliente informar duração (ex: "3 horas"), passe em duration_hours para calcular o check-out automaticamente.'
  end

  def tool_parameters_schema
    {
      type: 'object',
      properties: {
        suite: {
          type: 'string',
          description: 'Nome da suíte/categoria escolhida pelo cliente (ex: Stilo, Master)'
        },
        price: {
          type: 'number',
          description: 'Valor TOTAL da reserva (sem descontos de sinal). Ex: 60.0'
        },
        deposit_value: {
          type: 'number',
          description: 'Valor exato a ser cobrado no Pix agora (Sinal). Se informado, substitui o cálculo automático de 50%. Ex: 27.50'
        },
        check_in_at: {
          type: 'string',
          description: 'Data e horário EXATO de chegada do cliente, extraído da conversa. ' \
                       'Formatos aceitos: ISO8601 (ex: "2026-03-01T18:30:00"), ' \
                       '"HH:MM" para hoje (ex: "18:30"), ' \
                       'ou data completa (ex: "01/03/2026 18:30"). ' \
                       'OBRIGATÓRIO quando o cliente informar o horário de chegada.'
        },
        duration_hours: {
          type: 'number',
          description: 'Duração da estadia em horas (ex: 3.0). ' \
                       'Usado para calcular check_out = check_in + duração. ' \
                       'Passe este campo quando o cliente informar duração em vez de horário de saída.'
        },
        check_out_at: {
          type: 'string',
          description: 'Data e horário de saída, se informado explicitamente pelo cliente. Formato ISO8601 ou HH:MM.'
        }
      },
      required: %w[suite price]
    }
  end

  def execute(*args, **params)
    actual_params = resolve_params(args, params)
    Rails.logger.info "[CreateReservationIntentTool] Starting with params: #{actual_params}"

    suite_category = actual_params[:suite]
    price_raw = actual_params[:price].to_s.gsub(/[^\d,.]/, '').tr(',', '.')
    price = price_raw.to_f

    deposit_input = actual_params[:deposit_value].to_s.gsub(/[^\d,.]/, '').tr(',', '.')
    deposit_override = deposit_input.to_f if deposit_input.present?

    last_availability = fetch_last_availability

    if suite_category.blank? || price <= 0
      inferred = infer_from_history
      suite_category ||= inferred[:suite]
      price = inferred[:price].to_f if price <= 0 && inferred[:price].present?
    end

    if (suite_category.blank? || price <= 0) && last_availability.present?
      suite_category ||= last_availability[:suite]
      price = last_availability[:price].to_f if price <= 0 && last_availability[:price].present?
    end

    intent_error = verify_user_intent_barrier!(suite_category, @conversation)
    return intent_error if intent_error

    if price.positive? && last_availability.present? && !(deposit_override && deposit_override.positive?) && price_mismatch?(price,
                                                                                                                             last_availability[:price])
      msg = "ATENÇÃO: Preço (R$ #{format('%.2f',
                                         price)}) diverge da última cotação (R$ #{format('%.2f',
                                                                                         last_availability[:price])} para #{last_availability[:suite]}). NÃO crie a reserva. Corrija o valor ou peça para o usuário confirmar."
      Rails.logger.warn "[CreateReservationIntentTool] Price block: tried #{price} but last quote was #{last_availability[:price]}"
      return msg
    end

    return "SYSTEM INFO: Você esqueceu de informar a 'suite'. Pergunte ao cliente qual suíte e duração ele deseja." if suite_category.blank?

    return 'SYSTEM INFO: Preço inválido. Use consultar_disponibilidade.' if price <= 0

    ensure_conversation_context!

    return "Erro Crítico: Contexto de conversa não disponível. Params: #{actual_params}" unless @conversation&.inbox

    unit = infer_unit
    return 'Erro: Unidade não encontrada para esta conversa. Verifique se o Inbox está conectado a uma Unidade.' unless unit

    check_in_at, check_out_at = resolve_check_in_and_out(actual_params)

    recent_draft = Captain::Reservation.where(conversation_id: @conversation.id, status: :draft)
                                       .where('created_at > ?', 5.minutes.ago)
                                       .where(suite_identifier: suite_category)
                                       .order(created_at: :desc)
                                       .first

    deposit_amount = if deposit_override&.positive?
                       deposit_override
                     else
                       price / 2.0
                     end

    recent_draft_deposit = recent_draft&.metadata.to_h['deposit_amount'].to_f
    if recent_draft && (recent_draft_deposit - deposit_amount).abs < 0.1
      msg = "ATENÇÃO: A reserva JÁ FOI CRIADA anteriormente (ID: #{recent_draft.id}). NÃO crie novamente. Apenas CHAME A FERRAMENTA 'generate_pix' AGORA para finalizar."
      Rails.logger.info "[CreateReservationIntentTool] Idempotency hit: reusing draft #{recent_draft.id}"
      return msg
    end

    Captain::Reservation.where(conversation_id: @conversation.id, status: :draft).update_all(status: :cancelled)

    begin
      Captain::Reservation.create!(
        conversation_id: @conversation.id,
        account: @conversation.account,
        contact: @conversation.contact,
        contact_inbox: @conversation.contact_inbox,
        inbox: @conversation.inbox,
        captain_unit_id: unit.id,
        captain_brand_id: unit.captain_brand_id,
        suite_identifier: suite_category,
        status: :draft,
        total_amount: price,
        check_in_at: check_in_at,
        check_out_at: check_out_at,
        metadata: {
          full_amount: price,
          deposit_amount: deposit_amount
        }
      )

      update_sticky_state(
        suite: suite_category,
        price: deposit_amount,
        check_in_at: check_in_at,
        check_out_at: check_out_at
      )

      msg = "Reserva iniciada com sucesso! Check-in: #{check_in_at.strftime('%d/%m/%Y às %H:%M')}. " \
            "O valor do sinal (50%) é: #{ActiveSupport::NumberHelper.number_to_currency(deposit_amount,
                                                                                        unit: 'R$ ', separator: ',', delimiter: '.')}. " \
            'INSTRUÇÃO: Como a reserva foi criada com sucesso, avise o cliente e CHAME IMEDIATAMENTE a ferramenta generate_pix para entregar o código de pagamento.'
      Rails.logger.info '[CreateReservationIntentTool] Reservation created successfully'
      return msg
    rescue StandardError => e
      Rails.logger.error "[CreateReservationIntentTool] Creation failed: #{e.message} | #{e.backtrace&.first}"
      return "Erro técnico ao criar reserva: #{e.message}"
    end
  end

  private

  def verify_user_intent_barrier!(suite_category, conversation)
    return nil if suite_category.blank?

    all_incoming = conversation&.messages&.incoming&.order(created_at: :asc)&.last(10) || []
    last_reset_index = all_incoming.rindex { |m| m.content.to_s.downcase.match?(/\b(reiniciar|resetar|comecar de novo)\b/i) }

    relevant_messages = last_reset_index ? all_incoming[(last_reset_index + 1)..] : all_incoming
    user_text_post_reset = relevant_messages.map(&:content).join(' ').downcase
    user_text_post_reset = ActiveSupport::Inflector.transliterate(user_text_post_reset).gsub(/[^\w\s]/, '')

    aliases = {
      'hidromassagem' => %w[hidro banheira jacuzzi hidromassagem],
      'stilo' => %w[stilo estilo],
      'master' => %w[master],
      'alexa' => %w[alexa]
    }

    suite_key = suite_category.to_s.downcase.strip
    suite_key = ActiveSupport::Inflector.transliterate(suite_key)

    valid_terms = aliases[suite_key] || [suite_key]

    match_found = valid_terms.any? do |term|
      term_clean = ActiveSupport::Inflector.transliterate(term)
      user_text_post_reset.include?(term_clean)
    end

    Rails.logger.debug { "[CreateReservationIntentTool] Intent barrier: #{valid_terms} in '#{user_text_post_reset}' -> Match: #{match_found}" }

    unless match_found
      Rails.logger.info "[CreateReservationIntentTool] Intent blocked: Suite '#{suite_category}' not found after reset"
      return "Atenção: O usuário ainda não escolheu a suíte '#{suite_category}' nesta nova conversa. Pergunte: 'Qual suíte você gostaria de reservar?'."
    end

    nil
  end

  def resolve_check_in_and_out(params)
    c_in  = params[:check_in_at] || params[:date] || params[:day]
    c_out = params[:check_out_at]
    dur   = params[:duration_hours]&.to_f

    check_in = parse_flexible_datetime(c_in) || Time.zone.now.tomorrow.change(hour: 14)

    check_out = if c_out.present?
                  parse_flexible_datetime(c_out) || (check_in + 3.hours)
                elsif dur&.positive?
                  check_in + dur.hours
                else
                  check_in + 3.hours
                end

    [check_in, check_out]
  end

  # Interpreta múltiplos formatos de data/hora:
  # - "HH:MM" → hoje nesse horário
  # - "DD/MM/YYYY HH:MM" → data + hora
  # - ISO8601 → parse direto
  def parse_flexible_datetime(value)
    return nil if value.blank?

    str = value.to_s.strip

    # Formato "HH:MM" → hoje nesse horário
    if str.match?(/\A\d{1,2}:\d{2}\z/)
      hour, min = str.split(':').map(&:to_i)
      return Time.zone.now.change(hour: hour, min: min, sec: 0)
    end

    # Formato "DD/MM/YYYY HH:MM" ou "DD/MM/YYYY"
    if str.match?(%r{\A\d{1,2}/\d{1,2}/\d{2,4}})
      normalized = str.gsub(%r{(\d{1,2})/(\d{1,2})/(\d{2,4})}) do
        "#{Regexp.last_match(3)}-#{Regexp.last_match(2).rjust(2, '0')}-#{Regexp.last_match(1).rjust(2, '0')}"
      end
      return Time.zone.parse(normalized)
    end

    Time.zone.parse(str)
  rescue ArgumentError, TypeError
    nil
  end

  def price_mismatch?(price_a, price_b)
    (price_a.to_f - price_b.to_f).abs > 0.01
  end

  def ensure_conversation_context!
    return if @conversation.present?
  end

  def infer_unit
    @conversation&.inbox&.captain_inbox&.unit
  end

  def update_sticky_state(suite:, price:, check_in_at:, check_out_at:)
    return unless @conversation.respond_to?(:active_scenario_state)

    state = @conversation.active_scenario_state || {}
    collected = (state['collected'] || {}).merge(
      'suite' => suite,
      'price' => price,
      'check_in_at' => check_in_at&.iso8601,
      'check_out_at' => check_out_at&.iso8601
    ).compact

    @conversation.update!(
      active_scenario_state: state.merge(
        'stage' => 'reservation_intent_created',
        'collected' => collected,
        'updated_at' => Time.current.iso8601
      )
    )
  rescue StandardError => e
    Rails.logger.warn "[CreateReservationIntentTool] Failed to update sticky state: #{e.message}"
  end

  def fetch_last_availability
    return nil unless @conversation

    data = @conversation.custom_attributes&.fetch('last_availability', nil)
    return nil unless data.is_a?(Hash)

    captured_at = data['captured_at']
    return nil if captured_at.blank?

    if Time.zone.parse(captured_at) < 4.hours.ago
      Rails.logger.info '[CreateReservationIntent] Ignorando last_availability expirado (older than 4h)'
      return nil
    end

    data.with_indifferent_access
  end

  # Complexity is inherent: branches for reset detection + suite/price inference across messages
  def infer_from_history
    return {} if @conversation.blank?

    suite_candidates = available_suite_categories

    messages = @conversation.messages
                            .where(private: false)
                            .where('created_at >= ?', 4.hours.ago)
                            .order(created_at: :desc)
                            .limit(20).to_a

    reset_msg = messages.find { |m| m.content.to_s.downcase.match?(/\b(reiniciar|resetar|comecar de novo)\b/i) }
    messages = messages.take_while { |m| m.id != reset_msg.id } if reset_msg

    messages.each do |message|
      content = message.content.to_s
      suite = find_suite_in_text(content, suite_candidates)
      price = extract_price_from_text(content)

      return { suite: suite, price: price } if suite.present? || price.present?
    end

    {}
  end

  def available_suite_categories
    unit = infer_unit
    return %w[Stilo Master Hidromassagem] unless unit

    Captain::Pricing.where(captain_brand_id: unit.captain_brand_id).pluck(:suite_category).compact.uniq
  end

  def find_suite_in_text(content, suite_candidates)
    return nil if content.blank?

    suite_candidates.find { |suite| content.downcase.include?(suite.to_s.downcase) }
  end

  def extract_price_from_text(content)
    return nil if content.blank?

    match = content.match(/R\$\s*([\d\.]+,\d{2})/)
    return nil unless match

    match[1].tr('.', '').tr(',', '.').to_f
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize
# rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Layout/LineLength
# rubocop:enable Rails/SkipsModelValidations
