class Captain::Tools::GeneratePixTool < Captain::Tools::BaseTool
  CPF_WITH_LABEL_REGEX = /cpf[^\d]*(\d{3}\.?\d{3}\.?\d{3}-?\d{2}|\d{11})/i
  CPF_FALLBACK_REGEX = /\b\d{11}\b/
  NAME_WITH_LABEL_REGEX = /nome\s*[:\-]\s*([^\n\r,;]+)/i
  SUITE_REGEX = /su[ií]te\s+([^\n\r,.!?]+)/i
  DDMMYYYY_REGEX = %r{\b(\d{1,2}/\d{1,2}/\d{2,4})\b}
  CURRENCY_REGEX = /r\$\s*([\d.,]+)/i
  TOTAL_AMOUNT_REGEX = /valor\s+total[^\n\r]{0,80}/i
  DEPOSIT_AMOUNT_REGEX = /(sinal|entrada)[^\n\r]{0,80}/i
  NIGHTS_REGEX = /(\d+)\s*(?:noite|noites|di[aá]ria|di[aá]rias)/i
  ONE_NIGHT_REGEX = /\b(uma|um)\s+pernoite\b/i

  def name
    'generate_pix'
  end

  def description
    'Gera uma cobrança Pix para a reserva da conversa. Se ainda não existir rascunho, tenta criar automaticamente. ' \
      'Retorna um objeto com formatted_message (link de pagamento) e raw_payload (código copia e cola).'
  end

  def tool_parameters_schema
    {
      type: 'object',
      properties: {
        amount: {
          type: 'number',
          description: 'Opcional. Valor exato a cobrar. Se informado, substitui o valor padrão da reserva.'
        },
        suite: {
          type: 'string',
          description: 'Opcional. Nome da suíte.'
        },
        check_in: {
          type: 'string',
          description: 'Opcional. Data de check-in (YYYY-MM-DD ou DD/MM/YYYY).'
        },
        check_out: {
          type: 'string',
          description: 'Opcional. Data de check-out (YYYY-MM-DD ou DD/MM/YYYY).'
        },
        nights: {
          type: 'integer',
          description: 'Opcional. Quantidade de noites para inferir check-out.'
        },
        total_amount: {
          type: 'number',
          description: 'Opcional. Valor total da reserva.'
        }
      }
    }
  end

  MAX_PIX_AMOUNT = 50_000.0
  MIN_PIX_AMOUNT = 1.0

  def execute(*args, **params)
    actual_params = resolve_params(args, params)
    @conversation ||= resolve_conversation(args, params)
    return error_response('Erro técnico ao gerar o Pix. Não foi possível identificar a conversa atual.') if @conversation.blank?

    input_amount = actual_params[:amount].to_s.gsub(/[^\d,.]/, '').tr(',', '.')
    override_amount = input_amount.to_f if input_amount.present? && input_amount.to_f.positive?

    if override_amount
      return error_response("Valor mínimo para Pix é R$ #{format('%.2f', MIN_PIX_AMOUNT)}") if override_amount < MIN_PIX_AMOUNT
      return error_response("Valor máximo para Pix é R$ #{format('%.2f', MAX_PIX_AMOUNT)}") if override_amount > MAX_PIX_AMOUNT
    end

    contact = @conversation.contact
    hydrate_contact_identity_from_conversation!(contact, @conversation)
    return missing_cpf_response if contact_cpf(contact).blank?
    return missing_name_response if valid_contact_name?(contact.name).blank?

    # Verifica se já existe reserva pendente de pagamento
    pending = Captain::Reservation.where(conversation_id: @conversation.id, status: 'pending_payment').last
    return handle_pending_reservation(pending, override_amount) if pending

    reservation = find_recent_draft_reservation
    unless reservation
      reservation = ensure_draft_reservation!(actual_params, override_amount)
      return reservation if reservation.is_a?(Hash)
    end

    charge_amount = override_amount || default_charge_amount(reservation)
    merge_reservation_amount_metadata!(reservation, deposit_amount: charge_amount)
    Rails.logger.info "[GeneratePixTool] Reserva ID #{reservation.id} | Valor: #{charge_amount}"
    generate_new_pix(reservation, amount: charge_amount)
  end

  private

  def resolve_params(args, params)
    merged = params.to_h

    args.each do |arg|
      next unless arg.is_a?(Hash)
      next if tool_context_hash?(arg)

      merged = arg.merge(merged)
    end

    merged.with_indifferent_access
  end

  def hydrate_contact_identity_from_conversation!(contact, conversation)
    return if contact.blank? || conversation.blank?

    extracted = extract_identity_from_recent_messages(conversation)
    return if extracted.blank?

    updates = {}
    current_custom_attributes = contact.custom_attributes.to_h

    updates[:custom_attributes] = current_custom_attributes.merge('cpf' => extracted[:cpf]) if contact_cpf(contact).blank? && extracted[:cpf].present?

    updates[:name] = extracted[:name] if valid_contact_name?(contact.name).blank? && extracted[:name].present?

    return if updates.blank?

    contact.update!(updates)
    Rails.logger.info("[GeneratePixTool] Contato #{contact.id} hidratado com dados da conversa")
  rescue StandardError => e
    Rails.logger.warn("[GeneratePixTool] Falha ao hidratar contato #{contact&.id}: #{e.class} - #{e.message}")
  end

  def extract_identity_from_recent_messages(conversation)
    recent_messages = conversation.messages
                                  .where(message_type: :incoming, sender_type: 'Contact')
                                  .reorder(created_at: :desc)
                                  .limit(20)

    cpf = nil
    name = nil

    recent_messages.each do |message|
      content = normalize_text(message.content)
      next if content.blank?

      cpf ||= extract_cpf_from_text(content)
      name ||= extract_name_from_text(content)
      break if cpf.present? && name.present?
    end

    {
      cpf: cpf,
      name: name
    }.compact
  end

  def extract_cpf_from_text(text)
    text = normalize_text(text)
    candidate = text[CPF_WITH_LABEL_REGEX, 1]
    candidate ||= text[CPF_FALLBACK_REGEX]

    digits_only = candidate.to_s.gsub(/\D/, '')
    return if digits_only.length != 11

    digits_only
  end

  def extract_name_from_text(text)
    text = normalize_text(text)
    candidate = text[NAME_WITH_LABEL_REGEX, 1].to_s.squish
    return if candidate.blank? || candidate.length < 3

    candidate.titleize
  end

  def contact_cpf(contact)
    attrs = contact.custom_attributes.to_h.with_indifferent_access
    digits_only = attrs[:cpf].to_s.gsub(/\D/, '')
    return if digits_only.length != 11

    digits_only
  end

  def valid_contact_name?(name)
    candidate = name.to_s.squish
    return if candidate.blank?
    return unless candidate.match?(/\p{L}/)

    candidate
  end

  def missing_cpf_response
    normalize_payload(
      {
        formatted_message: 'Para gerar o Pix e seguir com sua reserva, preciso do seu CPF com 11 dígitos. ' \
                           'Pode me enviar agora? Se preferir, pode mandar só os números.',
        success: true,
        requires_input: true,
        missing_field: 'cpf'
      }
    )
  end

  def missing_name_response
    normalize_payload(
      {
        formatted_message: 'Perfeito. Para gerar o Pix, preciso confirmar seu nome completo. Pode me informar?',
        success: true,
        requires_input: true,
        missing_field: 'name'
      }
    )
  end

  def missing_reservation_details_response(missing_fields)
    labels = []
    labels << 'a suíte desejada' if missing_fields.include?('suite')
    labels << 'a data de check-in' if missing_fields.include?('check_in')
    labels << 'a duração da estadia (quantidade de noites)' if missing_fields.include?('check_out')
    labels << 'o valor total da reserva' if missing_fields.include?('amount')

    normalize_payload(
      {
        formatted_message: "Para gerar o Pix certinho, preciso confirmar #{human_sentence(labels)}. Pode me passar?",
        success: true,
        requires_input: true,
        missing_fields: missing_fields
      }
    )
  end

  def resolve_conversation(args, params)
    state = extract_state(args, params)
    return nil if state.blank?

    conversation_state = state[:conversation] || state['conversation'] || {}
    conversation_id = conversation_state[:id] || conversation_state['id']
    display_id = conversation_state[:display_id] || conversation_state['display_id']
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

    if source.respond_to?(:context)
      context = source.context
      return context[:state] || context['state'] if context.is_a?(Hash)
    end

    return nil unless source.is_a?(Hash)

    source[:state] || source['state'] || source.dig(:context, :state) || source.dig('context', 'state')
  end

  def tool_context_hash?(hash)
    hash.key?(:state) ||
      hash.key?('state') ||
      hash.key?(:context) ||
      hash.key?('context') ||
      hash.key?(:conversation) ||
      hash.key?('conversation')
  end

  def handle_pending_reservation(pending, override_amount)
    charge_amount = default_charge_amount(pending)

    if override_amount
      Rails.logger.info "[GeneratePixTool] Valor alterado para #{override_amount}. Forçando novo Pix."
      merge_reservation_amount_metadata!(pending, deposit_amount: override_amount)
      Captain::PixCharge.where(reservation_id: pending.id).update_all(status: 'expired')
      return generate_new_pix(
        pending,
        amount: override_amount,
        prefix: "Atualizei o valor para R$ #{format('%.2f', override_amount)}. Novo Pix abaixo:"
      )
    end

    charge = current_pix_charge_for(pending)
    if charge&.pix_copia_e_cola.present?
      if charge.expired? || charge.expired_by_time?
        charge.update!(status: 'expired') unless charge.expired?
        return generate_new_pix(pending, amount: charge_amount, prefix: 'Pix expirado. Gerando um novo agora.')
      end

      return build_pix_response(charge, pending, amount: charge_amount, prefix: 'Pix ainda válido. Segue abaixo para pagamento:')
    end

    generate_new_pix(pending, amount: charge_amount, prefix: 'Nenhuma cobrança ativa encontrada. Gerando um novo Pix.')
  end

  def error_response(msg)
    normalize_payload({ formatted_message: msg, success: false })
  end

  def tool_feedback_response(msg)
    normalize_payload({ formatted_message: msg, success: true })
  end

  def current_pix_charge_for(reservation)
    return nil unless reservation

    Captain::PixCharge.where(reservation_id: reservation.id).order(created_at: :desc).first
  end

  def generate_new_pix(reservation, amount: nil, prefix: nil)
    charge_amount = amount || default_charge_amount(reservation)
    service = Captain::Inter::CobService.new(reservation, amount: charge_amount)
    charge = service.call

    reservation.update!(status: 'pending_payment')
    mark_conversation_as_awaiting_payment(reservation)
    Rails.logger.info "[GeneratePixTool] Reserva #{reservation.id} → pending_payment"

    final_prefix = prefix || 'Cobrança Pix gerada com sucesso.'
    build_pix_response(charge, reservation, amount: charge_amount, prefix: final_prefix)
  rescue StandardError => e
    safe_error_message = normalize_text(e.message)
    Rails.logger.error("[GeneratePixTool] Falha ao gerar Pix: #{e.class} - #{safe_error_message}")
    mapped_error = map_pix_error_message(e)
    return mapped_error if mapped_error.is_a?(Hash)

    tool_feedback_response(mapped_error)
  end

  def map_pix_error_message(error)
    msg = normalize_text(error.message)
    msg_downcase = msg.downcase
    return missing_cpf_response if msg.match?(/cpf/i)

    if msg_downcase.include?('login/senha inválido') || msg_downcase.include?('login/senha invalido')
      return 'Não foi possível gerar o Pix — login/senha inválidos na integração Inter. Peça para o gestor revisar Client ID/Secret/certificados.'
    end
    if msg_downcase.include?('unit not configured for pix')
      return 'Não foi possível gerar o Pix — unidade não configurada para Pix. Revise chave Pix e dados Inter.'
    end
    if msg_downcase.include?('certificate file not found') || msg_downcase.include?('key file not found')
      return 'Não foi possível gerar o Pix — certificado ausente. Revise os arquivos .crt/.key da integração Inter.'
    end

    'Erro técnico ao gerar o Pix. Por favor, tente novamente em alguns instantes.'
  end

  def find_recent_draft_reservation
    Captain::Reservation.where(conversation_id: @conversation.id, status: 'draft')
                        .where('updated_at > ?', 2.hours.ago)
                        .order(created_at: :desc)
                        .first
  end

  def ensure_draft_reservation!(actual_params, override_amount)
    reservation_data = build_reservation_data(actual_params, override_amount)

    missing_fields = []
    missing_fields << 'suite' if reservation_data[:suite_identifier].blank?
    missing_fields << 'check_in' if reservation_data[:check_in_at].blank?
    missing_fields << 'check_out' if reservation_data[:check_in_at].present? && reservation_data[:check_out_at].blank?
    missing_fields << 'amount' if reservation_data[:total_amount].to_f <= 0
    return missing_reservation_details_response(missing_fields) if missing_fields.present?
    if @conversation.contact_inbox.blank?
      return error_response('Não consegui gerar o Pix porque este contato não está vinculado a esta caixa de entrada.')
    end

    reservation = Captain::Reservation.create!(
      account: @conversation.account,
      inbox: @conversation.inbox,
      contact: @conversation.contact,
      contact_inbox: @conversation.contact_inbox,
      conversation: @conversation,
      suite_identifier: reservation_data[:suite_identifier],
      check_in_at: reservation_data[:check_in_at],
      check_out_at: reservation_data[:check_out_at],
      status: :draft,
      payment_status: 'pending',
      total_amount: reservation_data[:total_amount],
      metadata: reservation_data[:metadata]
    )

    Rails.logger.info("[GeneratePixTool] Reserva draft criada automaticamente ##{reservation.id} para conversa #{@conversation.id}")
    reservation
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[GeneratePixTool] Falha ao criar reserva draft: #{e.record.errors.full_messages.join(', ')}")
    error_response('Não consegui preparar a reserva para gerar o Pix. Pode confirmar os dados da reserva para eu tentar novamente?')
  rescue StandardError => e
    Rails.logger.error("[GeneratePixTool] Erro ao criar reserva draft: #{e.class} - #{e.message}")
    error_response('Erro técnico ao preparar a reserva para o Pix. Por favor, tente novamente em instantes.')
  end

  def build_reservation_data(actual_params, override_amount)
    inferred = infer_reservation_data_from_conversation(@conversation)
    suite_identifier = normalize_suite_name(actual_params[:suite] || actual_params[:suite_identifier]) || inferred[:suite_identifier]
    check_in_at = parse_datetime_in_account_zone(actual_params[:check_in]) || inferred[:check_in_at]
    check_out_at = parse_datetime_in_account_zone(actual_params[:check_out]) || inferred[:check_out_at]

    nights = actual_params[:nights].to_i
    inferred_nights = inferred[:nights].to_i
    nights = inferred_nights if nights <= 0 && inferred_nights.positive?
    nights = 1 if nights <= 0
    check_out_at ||= infer_check_out_at(check_in_at, nights)

    parsed_total = parse_amount(actual_params[:total_amount])
    total_amount = parsed_total || inferred[:total_amount]
    deposit_amount = override_amount || inferred[:deposit_amount]
    total_amount ||= (deposit_amount * 2.0).round(2) if deposit_amount.present?

    metadata = {
      'full_amount' => total_amount&.to_f,
      'deposit_amount' => deposit_amount&.to_f,
      'created_by' => 'generate_pix_tool',
      'auto_intent' => true
    }.compact

    {
      suite_identifier: suite_identifier,
      check_in_at: check_in_at,
      check_out_at: check_out_at,
      total_amount: total_amount&.to_f,
      metadata: metadata
    }
  end

  def infer_reservation_data_from_conversation(conversation)
    return {} if conversation.blank?

    suite_identifier = nil
    check_in_date = nil
    nights = nil
    total_amount = nil
    deposit_amount = nil

    recent_messages_for_reservation_scan(conversation).each do |message|
      content = normalize_text(message.content)
      next if content.blank?

      suite_identifier ||= extract_suite_from_text(content)
      check_in_date ||= extract_check_in_date_from_text(content)
      nights ||= extract_nights_from_text(content)
      total_amount ||= extract_total_amount_from_text(content)
      deposit_amount ||= extract_deposit_amount_from_text(content)
      break if suite_identifier && check_in_date && nights && total_amount && deposit_amount
    end

    check_in_at = normalize_check_in_datetime(check_in_date)
    check_out_at = infer_check_out_at(check_in_at, nights || 1)

    {
      suite_identifier: suite_identifier,
      check_in_at: check_in_at,
      check_out_at: check_out_at,
      nights: nights,
      total_amount: total_amount,
      deposit_amount: deposit_amount
    }.compact
  end

  def recent_messages_for_reservation_scan(conversation)
    conversation.messages
                .where(message_type: %i[incoming outgoing], private: false)
                .reorder(created_at: :desc)
                .limit(30)
  end

  def extract_suite_from_text(text)
    text = normalize_text(text)
    raw_suite = text[SUITE_REGEX, 1].to_s.squish
    return if raw_suite.blank?

    normalize_suite_name(raw_suite)
  end

  def normalize_suite_name(raw_suite)
    cleaned = normalize_text(raw_suite)
              .gsub(/\b(amanh[ãa]|hoje|no dia)\b/i, '')
              .gsub(/\s+/, ' ')
              .strip
    return if cleaned.blank? || cleaned.length < 3

    cleaned
  end

  def extract_check_in_date_from_text(text)
    text = normalize_text(text)
    date_match = text[DDMMYYYY_REGEX, 1]
    return parse_date_value(date_match) if date_match.present?

    current_date = account_current_date
    return current_date + 2.days if text.match?(/depois\s+de\s+amanh[ãa]/i)
    return current_date + 1.day if text.match?(/\bamanh[ãa]\b/i)
    return current_date if text.match?(/\bhoje\b/i)

    nil
  end

  def extract_nights_from_text(text)
    text = normalize_text(text)
    return 1 if text.match?(ONE_NIGHT_REGEX)
    return 1 if text.match?(/\bpernoite\b/i)

    matches = text.scan(NIGHTS_REGEX)
    nights = matches.flatten.compact.map(&:to_i).find(&:positive?)
    nights if nights&.positive?
  end

  def extract_total_amount_from_text(text)
    text = normalize_text(text)
    segment = text[TOTAL_AMOUNT_REGEX]
    segment ||= text if text.match?(/valor\s+total/i)
    parse_amount_from_text(segment)
  end

  def extract_deposit_amount_from_text(text)
    text = normalize_text(text)
    segment = text[DEPOSIT_AMOUNT_REGEX]
    segment ||= text if text.match?(/sinal|entrada/i)
    parse_amount_from_text(segment)
  end

  def parse_amount_from_text(text)
    text = normalize_text(text)
    return if text.blank?

    raw = text[CURRENCY_REGEX, 1]
    parse_amount(raw)
  end

  def parse_amount(value)
    clean = normalize_text(value).gsub(/[^\d.,]/, '')
    return if clean.blank?

    normalized = if clean.include?(',')
                   clean.delete('.').tr(',', '.')
                 else
                   clean
                 end
    amount = normalized.to_f
    amount if amount.positive?
  end

  def parse_datetime_in_account_zone(raw_value)
    return if raw_value.blank?
    return normalize_check_in_datetime(raw_value) if raw_value.is_a?(Date) || raw_value.is_a?(Time)

    normalized_raw = normalize_text(raw_value)
    parsed_date = parse_date_value(normalized_raw)
    return normalize_check_in_datetime(parsed_date) if parsed_date.present?

    with_account_time_zone { Time.zone.parse(normalized_raw) }
  rescue ArgumentError, TypeError
    nil
  end

  def parse_date_value(raw_value)
    string_value = normalize_text(raw_value).strip
    return if string_value.blank?

    Date.strptime(string_value, '%d/%m/%Y')
  rescue ArgumentError
    begin
      Date.strptime(string_value, '%d/%m/%y')
    rescue ArgumentError
      begin
        Date.iso8601(string_value)
      rescue ArgumentError
        nil
      end
    end
  end

  def normalize_check_in_datetime(value)
    return if value.blank?

    return value.in_time_zone(account_timezone) if value.is_a?(Time)

    date = value.to_date
    with_account_time_zone { Time.zone.local(date.year, date.month, date.day, 19, 0, 0) }
  end

  def infer_check_out_at(check_in_at, nights)
    return if check_in_at.blank?

    total_nights = nights.to_i.positive? ? nights.to_i : 1
    check_out_date = check_in_at.to_date + total_nights.days
    with_account_time_zone { Time.zone.local(check_out_date.year, check_out_date.month, check_out_date.day, 12, 0, 0) }
  end

  def account_current_date
    with_account_time_zone { Time.zone.today }
  end

  def with_account_time_zone(&)
    Time.use_zone(account_timezone, &)
  end

  def account_timezone
    account = @conversation&.account
    configured_timezone = if account.respond_to?(:timezone)
                            account.timezone
                          elsif account.respond_to?(:time_zone)
                            account.time_zone
                          else
                            account&.settings&.dig('timezone')
                          end
    configured_timezone.presence || Time.zone.name
  end

  def human_sentence(labels)
    return labels.first.to_s if labels.length <= 1

    "#{labels[0..-2].join(', ')} e #{labels.last}"
  end

  def normalize_text(value)
    value.to_s
         .dup
         .force_encoding(Encoding::UTF_8)
         .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
  rescue StandardError
    value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
  end

  def normalize_payload(value)
    case value
    when String
      normalize_text(value)
    when Array
      value.map { |item| normalize_payload(item) }
    when Hash
      normalized = value.each_with_object({}) do |(key, item), acc|
        normalized_key = key.is_a?(String) ? normalize_text(key) : key
        acc[normalized_key] = normalize_payload(item)
      end
      value.is_a?(ActiveSupport::HashWithIndifferentAccess) ? normalized.with_indifferent_access : normalized
    else
      value
    end
  end

  def build_pix_response(charge, reservation, amount:, prefix: nil)
    intro = prefix.present? ? "#{prefix}\n\n" : ''

    base_url = InstallationConfig.find_by(name: 'FRONTEND_URL')&.value.presence ||
               ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    base_url = base_url.gsub('0.0.0.0', '127.0.0.1') if base_url.include?('0.0.0.0')

    token = charge.to_sgid(expires_in: 2.hours, purpose: :pix_payment).to_s
    link  = Rails.application.routes.url_helpers.short_payment_link_url(token, host: base_url)

    instructions = "Para facilitar, gerei um link de pagamento rápido com botão COPIAR.\n" \
                   "1. Clique no link abaixo\n" \
                   "2. Aperte 'COPIAR CÓDIGO PIX'\n" \
                   "3. Cole no app do seu banco e pague.\n\n" \
                   "Link Seguro: #{link}\n\n" \
                   '(IMPORTANTE PARA A I.A.: Envie este link EXATAMENTE como está acima. NÃO use formatação Markdown [texto](url). ' \
                   'O WhatsApp não reconhece. Envie APENAS a URL pura, solta no texto.)'

    final_code = charge.pix_copia_e_cola.to_s.strip
    if final_code.start_with?('/spi/')
      header = '00020101021226930014BR.GOV.BCB.PIX2571spi-qrcode.bancointer.com.br'
      final_code = "#{header}#{final_code}"
    end

    final_code = normalize_text(final_code)

    normalize_payload(
      {
        formatted_message: "#{intro}#{instructions}",
        raw_payload: final_code,
        payment_link: link,
        amount: amount.to_f,
        reservation_id: reservation.id,
        success: true
      }
    )
  end

  def default_charge_amount(reservation)
    metadata = reservation.metadata.to_h
    configured = metadata['deposit_amount']
    return configured.to_f if configured.present? && configured.to_f.positive?

    (reservation.total_amount.to_f / 2.0).round(2)
  end

  def merge_reservation_amount_metadata!(reservation, deposit_amount:)
    metadata = reservation.metadata.to_h
    merged = metadata.merge(
      'full_amount' => metadata['full_amount'].presence || reservation.total_amount.to_f,
      'deposit_amount' => deposit_amount.to_f
    )
    reservation.update!(metadata: merged)
  end

  def mark_conversation_as_awaiting_payment(reservation)
    conversation = reservation.conversation || @conversation
    return if conversation.blank?

    current = conversation.label_list
    merged  = (current + ['aguardando_pagamento']).uniq
    merged -= %w[pagamento_confirmado reserva_feita]
    conversation.update_labels(merged)
  end
end
