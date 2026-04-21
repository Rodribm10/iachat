# frozen_string_literal: true

# rubocop:disable Metrics/ClassLength,Metrics/AbcSize
# Consulta preco direto no Supabase (schema reserva_hotel) a partir da
# marca/unidade vinculada ao inbox da conversa atual. Substitui o uso de
# faq_lookup para perguntas de preco - garante valor correto e atualizado.
class Captain::Tools::GetReservaPrecoTool < Captain::Tools::BaseTool
  DEFAULT_SCHEMA = 'reserva_hotel'

  def name
    'get_reserva_preco'
  end

  def description
    <<~DESC.strip
      Consulta o preco de uma suite direto no banco de reservas (fonte oficial).
      USE SEMPRE que o cliente perguntar valor/preco de categoria + permanencia.
      NAO use faq_lookup para preco - use esta tool. Retorna o valor exato,
      ja considerando o periodo da semana (segunda-quinta, sexta, sabado, etc).
      A marca e resolvida automaticamente pelo inbox da conversa.
    DESC
  end

  def tool_parameters_schema
    {
      type: 'object',
      required: %w[categoria permanencia],
      properties: {
        categoria: {
          type: 'string',
          description: 'OBRIGATORIO. Nome da categoria/suite. Ex: "Alexa", "Stilo", "Hidromassagem".'
        },
        permanencia: {
          type: 'string',
          description: 'OBRIGATORIO. Permanencia. Ex: "2hrs", "3hrs", "4hrs", "Pernoite", "Diaria".'
        },
        checkin_at: {
          type: 'string',
          description: 'OPCIONAL. Data/hora de check-in em ISO 8601. Usado para resolver periodo da semana. ' \
                       'Se vazio, usa periodo "default".'
        }
      }
    }
  end

  def execute(*args, **params)
    actual_params = resolve_params(args, params)
    @conversation ||= resolve_conversation(args, params)

    categoria = actual_params[:categoria].to_s.strip
    permanencia = actual_params[:permanencia].to_s.strip
    checkin_at = actual_params[:checkin_at].to_s.strip

    return missing_fields_response(categoria, permanencia) if categoria.empty? || permanencia.empty?

    unit = infer_unit
    return error_response('Inbox desta conversa nao esta vinculado a uma unidade. Nao consigo buscar preco.') if unit.blank?

    unit_row = fetch_unidade(unit.id)
    return error_response("Unidade #{unit.id} nao encontrada no banco de reservas (reserva_hotel.unidades).") if unit_row.blank?

    tenant_id = unit_row['tenant_id']
    marca_id = unit_row['id_marca']

    periodo_slug = resolve_periodo_slug(marca_id, checkin_at)
    preco_row = fetch_preco(tenant_id, marca_id, categoria, permanencia, periodo_slug)

    return preco_not_found_response(categoria, permanencia, periodo_slug) if preco_row.blank?

    success_response(preco_row, categoria, permanencia)
  rescue StandardError => e
    Rails.logger.error("[GetReservaPrecoTool] falha: #{e.class} - #{e.message}")
    error_response('Nao consegui consultar o preco agora. Tente novamente em instantes.')
  end

  private

  def infer_unit
    @conversation&.inbox&.captain_inbox&.unit
  end

  def fetch_unidade(chatwoot_unit_id)
    data = supabase_get(
      'unidades',
      {
        'chatwoot_unit_id' => "eq.#{chatwoot_unit_id}",
        'select' => 'id,id_marca,tenant_id,nome'
      }
    )
    Array(data).first
  end

  def resolve_periodo_slug(marca_id, checkin_at)
    return 'default' if checkin_at.to_s.strip.empty?

    day_of_week = Time.zone.parse(checkin_at).wday # 0=dom..6=sab
    periodos = supabase_get(
      'marca_periodos',
      {
        'id_marca' => "eq.#{marca_id}",
        'ativo' => 'eq.true',
        'select' => 'slug,dias,ordem',
        'order' => 'ordem.asc'
      }
    )

    matched = Array(periodos).find do |p|
      dias = p['dias']
      dias.is_a?(Array) && dias.include?(day_of_week)
    end

    matched&.dig('slug') || 'default'
  rescue ArgumentError, TypeError
    'default'
  end

  def fetch_preco(tenant_id, marca_id, categoria, permanencia, periodo_slug)
    data = supabase_get(
      'precos',
      {
        'tenant_id' => "eq.#{tenant_id}",
        'id_marca' => "eq.#{marca_id}",
        'categoria' => "eq.#{categoria}",
        'permanencia' => "eq.#{permanencia}",
        'periodo_semana' => "eq.#{periodo_slug}",
        'ativo' => 'eq.true',
        'select' => 'valor,categoria,permanencia,periodo_semana',
        'limit' => '1'
      }
    )
    Array(data).first
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
  rescue JSON::ParserError => e
    Rails.logger.warn("[GetReservaPrecoTool] JSON parse error: #{e.message}")
    []
  end

  def supabase_client
    @supabase_client ||= Faraday.new do |f|
      f.request :url_encoded
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

  def success_response(preco_row, categoria, permanencia)
    valor = preco_row['valor'].to_f
    formatted = ActiveSupport::NumberHelper.number_to_currency(
      valor, unit: 'R$ ', separator: ',', delimiter: '.'
    )
    periodo = preco_row['periodo_semana']

    {
      formatted_message: "#{categoria} (#{permanencia}) - #{formatted} [periodo: #{periodo}]. " \
                         'Valor oficial do banco de reservas.',
      success: true,
      valor: valor,
      valor_formatado: formatted,
      categoria: categoria,
      permanencia: permanencia,
      periodo_semana: periodo
    }
  end

  def preco_not_found_response(categoria, permanencia, periodo_slug)
    {
      formatted_message: "Nao encontrei preco cadastrado para #{categoria} / #{permanencia} " \
                         "(periodo: #{periodo_slug}). Consulte o admin para cadastrar esse valor.",
      success: false
    }
  end

  def missing_fields_response(categoria, permanencia)
    missing = []
    missing << 'categoria' if categoria.empty?
    missing << 'permanencia' if permanencia.empty?
    {
      formatted_message: "Preciso de: #{missing.join(', ')}. Pergunte ao cliente e chame a tool de novo.",
      success: false,
      missing_fields: missing
    }
  end

  def error_response(message)
    { formatted_message: message, success: false }
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

  # Copiado de GenerateReservationLinkTool
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

  def tool_context_hash?(hash)
    hash.key?(:state) || hash.key?('state') ||
      hash.key?(:context) || hash.key?('context') ||
      hash.key?(:conversation) || hash.key?('conversation')
  end
end
# rubocop:enable Metrics/ClassLength,Metrics/AbcSize
