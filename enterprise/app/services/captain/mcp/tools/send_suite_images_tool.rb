# Tool MCP: envia fotos de suítes pro cliente.
#
# Caso de uso: cliente pede pra ver foto da suíte antes de fechar
# ("manda uma foto da Master?", "tem como ver?"). Tool busca o catálogo
# Captain::GalleryItem da inbox atual (com fallback pra acervo global) e
# envia até `limit` imagens como mensagens outgoing na conversa.
#
# Search: aceita `suite_category` (nome da categoria configurada na unidade)
# OU `suite_number` (ex: "101"), mutuamente exclusivos. Match case-insensitive,
# fuzzy. NÃO incluir exemplos de categorias específicas aqui — vaza pro LLM
# em outros agentes via tools/list.
#
# Pré-requisito: cadastro do Captain::GalleryItem via painel UI do
# Chatwoot — Captain::Mcp não cria fotos, só consome o catálogo.
class Captain::Mcp::Tools::SendSuiteImagesTool < Captain::Mcp::Tools::BaseTool
  DEFAULT_LIMIT = 3
  MAX_LIMIT = 5
  PHOTO_SENT_LABEL = 'ia_foto_enviada'.freeze

  class << self
    def name
      'send_suite_images'
    end

    def description
      'Envia fotos da suíte pra conversa do cliente. Use quando ele pedir foto/imagem ' \
        '("manda uma foto", "tem como ver?"). Busca no catálogo da inbox atual (fallback ' \
        'global). Passe `suite_category` (nome da categoria conforme cadastro da unidade) ' \
        'OU `suite_number` (ex: "101") — não combine os dois.'
    end

    def input_schema # rubocop:disable Metrics/MethodLength
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid do [ctx]). Obrigatório.'
          },
          suite_category: {
            type: 'string',
            description: 'Nome/tipo da suíte conforme cadastro da unidade. Use quando o cliente pede pelo NOME da categoria.'
          },
          suite_number: {
            type: 'string',
            description: 'Número específico da suíte (ex: "101"). Use quando o cliente pede pelo NÚMERO. Mutuamente exclusivo com suite_category.'
          },
          limit: {
            type: 'integer',
            description: "Quantas fotos enviar (default #{DEFAULT_LIMIT}, máx #{MAX_LIMIT}).",
            default: DEFAULT_LIMIT
          }
        },
        required: ['conversation_id']
      }
    end
  end

  def call(args, context:) # rubocop:disable Metrics/AbcSize
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]).') if conversation.blank?

    suite_category = args['suite_category'].to_s.strip
    suite_number = args['suite_number'].to_s.strip
    return error_response('Passe suite_category OU suite_number — pelo menos um.') if suite_category.blank? && suite_number.blank?

    items = find_items(conversation, suite_category, suite_number, args['limit'].to_i)
    if items.blank?
      label = suite_category.presence || suite_number
      return text_response("Nenhuma foto cadastrada pra #{label}. Avise o cliente que pode pedir pro humano.")
    end

    sent = items.count { |item| send_image_message(conversation, item) }
    return error_response('Encontrei fotos na galeria, mas não consegui enviar nenhuma imagem.') if sent.zero?

    add_photo_sent_label(conversation)

    label = suite_category.presence || "suíte #{suite_number}"
    text_response("#{sent} foto(s) de #{label} enviadas na conversa #{conversation.display_id}.")
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::SendSuiteImagesTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao enviar fotos: #{e.message}")
  end

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  def find_items(conversation, suite_category, suite_number, limit)
    base = Captain::GalleryItem
           .active
           .where(account_id: conversation.account_id)
           .includes(image_attachment: :blob)
           .ordered

    filtered = if suite_number.present?
                 base.where('LOWER(suite_number) = ?', suite_number.downcase)
               else
                 base.where(
                   'LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(suite_category, ' \
                   "'ã','a'),'â','a'),'á','a'),'à','a'),'é','e'),'ê','e')) " \
                   '= LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(?, ' \
                   "'ã','a'),'â','a'),'á','a'),'à','a'),'é','e'),'ê','e'))",
                   suite_category
                 )
               end

    inbox_scoped = filtered.where(scope: 'inbox', inbox_id: conversation.inbox_id)
    pool = inbox_scoped.exists? ? inbox_scoped : filtered.where(scope: 'global')

    pool.limit(normalize_limit(limit))
  end

  def normalize_limit(value)
    n = value.to_i
    return DEFAULT_LIMIT if n <= 0

    [n, MAX_LIMIT].min
  end

  def send_image_message(conversation, item)
    return false unless item.image.attached?

    Messages::MessageBuilder.new(
      nil,
      conversation,
      content: item.description.to_s.truncate(220),
      message_type: 'outgoing',
      attachments: [item.image.blob.signed_id]
    ).perform
    true
  rescue StandardError => e
    Rails.logger.warn("[Captain::Mcp::SendSuiteImagesTool] failed sending item #{item.id}: #{e.class} - #{e.message}")
    false
  end

  def add_photo_sent_label(conversation)
    Label.find_or_create_by!(account: conversation.account, title: PHOTO_SENT_LABEL) do |label|
      label.color = '#38bdf8'
      label.description = 'Aplicada automaticamente quando a IA envia fotos de suíte com sucesso.'
      label.show_on_sidebar = false
    end
    return if conversation.label_list.include?(PHOTO_SENT_LABEL)

    conversation.add_labels(PHOTO_SENT_LABEL)
  end
end
