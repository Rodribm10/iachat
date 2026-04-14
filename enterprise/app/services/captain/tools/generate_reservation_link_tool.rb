# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength,Metrics/MethodLength,Metrics/AbcSize
# Ferramenta que gera um link pré-preenchido da página pública de reserva
# (reserva-1001). A Jasmine invoca isso após coletar os dados do cliente
# em conversa e envia a URL como mensagem outgoing.
class Captain::Tools::GenerateReservationLinkTool < Captain::Tools::BaseTool
  DEFAULT_BASE_URL = 'http://localhost:5180'

  def name
    'generate_reservation_link'
  end

  def description
    <<~DESC.strip
      FALLBACK para gerar reserva via pagina publica (Reserva Rede 1001).
      Use SOMENTE quando `generate_pix` retornar success=false na mesma conversa.
      OBRIGATORIO passar: marca, unidade, categoria, permanencia, checkin_at.
      Nome/telefone/CPF/email vem do contato automaticamente.
      Retorna uma URL que DEVE ser enviada ao cliente como texto puro (sem markdown).
    DESC
  end

  def tool_parameters_schema
    {
      type: 'object',
      required: %w[marca unidade categoria permanencia checkin_at],
      properties: {
        marca: {
          type: 'string',
          description: 'OBRIGATORIO. Nome da marca. Ex: "Hotel 1001 Noites Prime".'
        },
        unidade: {
          type: 'string',
          description: 'OBRIGATORIO. Nome da unidade. Ex: "Prime Aguas Lindas".'
        },
        categoria: {
          type: 'string',
          description: 'OBRIGATORIO. Categoria da suite. Ex: "Alexa", "Stilo", "Hidromassagem".'
        },
        permanencia: {
          type: 'string',
          description: 'OBRIGATORIO. Permanencia escolhida. Ex: "2hrs", "3hrs", "4hrs", "Pernoite", "Diaria".'
        },
        checkin_at: {
          type: 'string',
          description: 'OBRIGATORIO. Check-in em ISO 8601. Ex: "2026-04-28T22:00:00". Default: ' \
                       '22:00 para Pernoite/Diaria, +1h do horario atual para 2hrs/3hrs/4hrs.'
        },
        email: {
          type: 'string',
          description: 'OPCIONAL. Email do cliente (se tiver).'
        },
        observacao: {
          type: 'string',
          description: 'OPCIONAL. Preferencia especial do cliente.'
        }
      }
    }
  end

  REQUIRED_STAY_FIELDS = %i[marca unidade categoria permanencia checkin_at].freeze

  def execute(*args, **params)
    actual_params = resolve_params(args, params)
    missing = REQUIRED_STAY_FIELDS.reject { |f| actual_params[f].to_s.strip.present? }

    if missing.any?
      return {
        formatted_message: "Nao posso gerar o link sem: #{missing.join(', ')}. " \
                           'Colete esses dados na conversa e chame a ferramenta de novo.',
        success: false,
        missing_fields: missing
      }
    end

    conversation = resolve_conversation(args, params)
    enriched_params = enrich_with_contact(actual_params, conversation)

    base = ENV.fetch('RESERVA_1001_BASE_URL', DEFAULT_BASE_URL)
    query = build_query(enriched_params)
    url = "#{base}/?#{query}"

    # Envia o link como mensagem direta pra garantir que chegue no WhatsApp
    # mesmo que a LLM parafraseie com placeholder [Link da reserva] etc.
    dispatch_direct_link_message(conversation, url)

    {
      formatted_message: url,
      raw_payload: url,
      success: true
    }
  rescue StandardError => e
    Rails.logger.error("[GenerateReservationLinkTool] falha: #{e.class} - #{e.message}")
    { formatted_message: 'Nao consegui gerar o link agora. Tente novamente em instantes.', success: false }
  end

  private

  # Params passados pela Jasmine vencem. Se nao passou, preenche com dados do contato.
  def enrich_with_contact(actual_params, conversation)
    return actual_params if conversation.blank?

    contact = conversation.contact
    return actual_params if contact.blank?

    custom = contact.custom_attributes || {}
    additional = contact.additional_attributes || {}

    {
      marca: actual_params[:marca],
      unidade: actual_params[:unidade],
      permanencia: actual_params[:permanencia],
      categoria: actual_params[:categoria],
      checkin_at: actual_params[:checkin_at],
      nome: actual_params[:nome].presence || contact.name.presence,
      telefone: actual_params[:telefone].presence || contact.phone_number.presence,
      cpf: actual_params[:cpf].presence || custom['cpf'].presence || additional['cpf'].presence,
      email: actual_params[:email].presence || contact.email.presence,
      observacao: actual_params[:observacao]
    }.compact
  end

  def dispatch_direct_link_message(conversation, url)
    return if conversation.blank? || url.to_s.strip.empty?

    content = "Link da sua reserva (tudo ja preenchido):\n#{url}"
    Messages::MessageBuilder.new(@assistant, conversation, {
                                   content: content,
                                   message_type: 'outgoing'
                                 }).perform
  rescue StandardError => e
    Rails.logger.warn("[GenerateReservationLinkTool] failed to dispatch link: #{e.class} - #{e.message}")
  end

  def build_query(actual_params)
    mapping = {
      marca: actual_params[:marca],
      unidade: actual_params[:unidade],
      permanencia: actual_params[:permanencia],
      categoria: actual_params[:categoria],
      checkin: actual_params[:checkin_at],
      nome: actual_params[:nome],
      telefone: actual_params[:telefone],
      cpf: actual_params[:cpf],
      email: actual_params[:email],
      obs: actual_params[:observacao]
    }
    cleaned = mapping.compact.reject { |_, v| v.to_s.strip.empty? }
    URI.encode_www_form(cleaned)
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

  # Copiado de CheckPixPaymentTool (enterprise/app/services/captain/tools/check_pix_payment_tool.rb:157-227)
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
end
# rubocop:enable Metrics/ClassLength,Metrics/MethodLength,Metrics/AbcSize
