# rubocop:disable Metrics/ClassLength
class Captain::Tools::SendSuiteImagesTool < Captain::Tools::BaseTool
  DEFAULT_LIMIT = 3
  MAX_LIMIT = 5

  def name
    'send_suite_images'
  end

  def description
    'Envia fotos de suítes para o cliente usando a galeria da caixa de entrada atual, com fallback para acervo global.'
  end

  # rubocop:disable Metrics/MethodLength
  def tool_parameters_schema
    {
      type: 'object',
      properties: {
        suite_category: {
          type: 'string',
          description: 'Opcional. Categoria da suíte (ex: luxo, hidro, master).'
        },
        suite_number: {
          type: 'string',
          description: 'Opcional. Número/identificador da suíte (ex: 101, alexa, aluba).'
        },
        limit: {
          type: 'integer',
          description: 'Opcional. Quantidade de imagens para enviar (padrão: 3, máximo: 5).'
        },
        inbox_id: {
          type: 'integer',
          description: 'Opcional. Força uma caixa de entrada específica para busca das fotos.'
        },
        captain_unit_id: {
          type: 'integer',
          description: 'Opcional (legado). Filtra por uma unidade específica dentro da galeria.'
        }
      }
    }
  end
  # rubocop:enable Metrics/MethodLength

  def execute(*args, **params)
    actual_params = resolve_params(args, params)
    @conversation ||= resolve_conversation(args, params)
    return error_response('Erro técnico ao enviar fotos. Não consegui identificar a conversa atual.') if @conversation.blank?

    selected_items = find_selected_items(actual_params)
    return no_images_response(actual_params) if selected_items.blank?

    sent_count = send_images(selected_items)
    success_payload(selected_items, sent_count, actual_params)
  rescue StandardError => e
    Rails.logger.error("[SendSuiteImagesTool] Falha ao enviar fotos: #{e.class} - #{normalize_text(e.message)}")
    error_response('Não consegui enviar as fotos agora. Tente novamente em instantes.')
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

  def find_items(actual_params)
    scope = Captain::GalleryItem
            .active
            .where(account_id: @conversation.account_id)
            .includes(image_attachment: :blob)
            .ordered

    unit_id = actual_params[:captain_unit_id].presence
    scope = scope.where(captain_unit_id: unit_id) if unit_id.present?

    category = normalize_filter(actual_params[:suite_category])
    suite_number = normalize_filter(actual_params[:suite_number])

    scope = scope.where('LOWER(suite_category) = ?', category.downcase) if category.present?
    scope = scope.where('LOWER(suite_number) = ?', suite_number.downcase) if suite_number.present?

    inbox_scope = scope.where(scope: 'inbox', inbox_id: resolve_target_inbox_id(actual_params))
    return inbox_scope if inbox_scope.exists?

    scope.where(scope: 'global')
  end

  def find_selected_items(actual_params)
    items = find_items(actual_params)
    return items if items.blank?

    items.limit(normalize_limit(actual_params[:limit]))
  end

  def send_images(items)
    items.count do |item|
      next false unless item.image.attached?

      Messages::MessageBuilder.new(@assistant, @conversation, {
                                     content: item.description.to_s.truncate(220),
                                     message_type: 'outgoing',
                                     attachments: [item.image.blob.signed_id]
                                   }).perform
      true
    end
  end

  def normalize_limit(value)
    parsed = value.to_i
    parsed = DEFAULT_LIMIT if parsed <= 0
    [parsed, MAX_LIMIT].min
  end

  def normalize_filter(value)
    value.to_s.strip.presence
  end

  def resolve_target_inbox_id(actual_params)
    requested_inbox_id = actual_params[:inbox_id].presence
    return @conversation.inbox_id if requested_inbox_id.blank?

    Inbox.where(account_id: @conversation.account_id, id: requested_inbox_id).pick(:id) || @conversation.inbox_id
  end

  def no_images_response(actual_params)
    category = normalize_filter(actual_params[:suite_category])
    suite_number = normalize_filter(actual_params[:suite_number])

    detail = []
    detail << "categoria #{category}" if category.present?
    detail << "suíte #{suite_number}" if suite_number.present?
    detail_text = detail.present? ? " para #{detail.join(' e ')}" : ''

    success_response("Não encontrei fotos cadastradas na galeria desta caixa de entrada nem no acervo global#{detail_text}.")
  end

  def success_payload(selected_items, sent_count, actual_params)
    scope_used = selected_items.first&.scope || 'inbox'
    scope_label = scope_used == 'global' ? 'acervo global' : 'caixa de entrada atual'

    success_response(
      "Enviei #{sent_count} foto(s) da galeria da #{scope_label} para te ajudar a escolher.",
      scope: scope_used,
      sent_count: sent_count,
      suite_category: actual_params[:suite_category],
      suite_number: actual_params[:suite_number]
    )
  end

  def success_response(message, metadata = {})
    {
      formatted_message: message,
      success: true
    }.merge(metadata)
  end

  def error_response(message)
    {
      formatted_message: message,
      success: false
    }
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
