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

    label = suite_category.presence || "suíte #{suite_number}"
    deliverable = items.select { |item| stored?(item) }
    return missing_file_response(items, label) if deliverable.blank?

    sent = deliverable.count { |item| send_image_message(conversation, item) }
    return error_response("Não consegui enviar as fotos de #{label} agora. NÃO diga ao cliente que enviou.") if sent.zero?

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

  # O registro do blob pode existir sem o arquivo no storage (ex: volume trocado
  # num redeploy). Sem essa checagem a mensagem é criada, o envio falha depois no
  # provider e a tool devolve "enviei" — o assistente promete foto que nunca chega.
  def stored?(item)
    item.image.attached? && item.image.blob.service.exist?(item.image.blob.key)
  rescue StandardError => e
    Rails.logger.warn("[Captain::Mcp::SendSuiteImagesTool] blob ilegível no item #{item.id}: #{e.class} - #{e.message}")
    false
  end

  def missing_file_response(items, label)
    Rails.logger.error(
      "[Captain::Mcp::SendSuiteImagesTool] arquivo ausente no storage para os itens #{items.map(&:id).join(',')}"
    )
    error_response(
      "As fotos de #{label} estão cadastradas mas o arquivo não está disponível no servidor. " \
      'NÃO diga ao cliente que enviou a foto — avise que o time vai enviar em seguida.'
    )
  end

  # `description` é cadastro interno (serve pro LLM escolher a foto) — jamais vira
  # legenda: já vazou instrução tipo "envie quando o cliente perguntar preço" pro cliente.
  # A foto vai sem legenda; quem escreve o texto é o assistente.
  def send_image_message(conversation, item)
    Messages::MessageBuilder.new(
      nil,
      conversation,
      content: nil,
      message_type: 'outgoing',
      attachments: [item.image.blob.signed_id]
    ).perform
    true
  rescue StandardError => e
    Rails.logger.warn("[Captain::Mcp::SendSuiteImagesTool] failed sending item #{item.id}: #{e.class} - #{e.message}")
    false
  end
end
