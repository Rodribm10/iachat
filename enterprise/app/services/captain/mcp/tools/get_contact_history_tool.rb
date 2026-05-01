# Tool MCP: retorna histórico estruturado do cliente em markdown.
#
# **Determinístico:** o conteúdo é montado on-the-fly do DB do Captain.
# LLM nunca escreve nem altera. Captain é source of truth único — Reservation,
# Conversation, Message, PixCharge etc — esta tool só serializa em markdown
# numa forma amigável pro LLM ler.
#
# Quando usar (do ponto de vista da Valentina):
#   - Cliente pergunta sobre passado livre ("o que falamos sobre alergia?")
#   - Cliente pede recap ("me lembra o que tava combinado?")
#   - Cliente pergunta sobre reserva antiga não-recente (recente já vem no [ctx])
#   - Suspeita de cliente VIP / fidelizado pra calibrar tom
#
# Quando NÃO usar:
#   - Pergunta cobertas pelo [ctx] (last_res_*, total_reservas) — responda direto
#   - Toda mensagem (custo de latência desnecessário)
class Captain::Mcp::Tools::GetContactHistoryTool < Captain::Mcp::Tools::BaseTool
  MAX_RESERVATIONS = 8
  MAX_CONVERSATIONS = 5
  MAX_MESSAGE_SAMPLES_PER_CONV = 6

  class << self
    def name
      'get_contact_history'
    end

    def description
      'Retorna histórico completo do cliente em markdown (reservas, conversas anteriores, ' \
        'labels, mensagens-chave). Use quando o cliente perguntar sobre algo do passado que ' \
        'não está no [ctx] (ex: "qual era a reserva de 3 meses atrás", "o que falamos sobre X"). ' \
        'NÃO use pra perguntas cobertas pelo [ctx] (last_res_date, total_reservas etc).'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          contact_id: {
            type: 'integer',
            description: 'ID do contato (campo `contact` do [ctx]). Obrigatório.'
          },
          query: {
            type: 'string',
            description: 'Opcional. Termo pra filtrar mensagens por conteúdo (ex: "alergia", "desconto"). Se vazio, retorna histórico geral.'
          }
        },
        required: ['contact_id']
      }
    end
  end

  def call(args, context:)
    contact_id = args['contact_id'].presence || context[:contact_id]
    return error_response('contact_id obrigatório.') if contact_id.blank?

    contact = Contact.find_by(id: contact_id)
    return error_response("Contato #{contact_id} não encontrado.") if contact.blank?

    md = build_markdown(contact, args['query'].to_s.strip)
    text_response(md)
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::GetContactHistoryTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao buscar histórico: #{e.message}")
  end

  private

  def build_markdown(contact, query)
    sections = []
    sections << header_section(contact)
    sections << reservations_section(contact)
    sections << conversations_section(contact, query)
    sections.compact.join("\n\n")
  end

  def header_section(contact)
    custom = contact.custom_attributes.to_h.with_indifferent_access
    cpf = custom[:cpf].to_s
    cpf_fmt = cpf.length == 11 ? cpf.gsub(/(\d{3})(\d{3})(\d{3})(\d{2})/, '\1.\2.\3-\4') : cpf

    [
      "# Cliente: #{contact.name} (contact #{contact.id})",
      ([
        cpf.present? ? "**CPF:** #{cpf_fmt}" : nil,
        contact.email.present? ? "**Email:** #{contact.email}" : nil,
        contact.phone_number.present? ? "**Telefone:** #{contact.phone_number}" : nil
      ].compact.join(' · ')).presence,
      ("**Notas:** #{custom[:notes]}" if custom[:notes].present?)
    ].compact.join("\n")
  end

  def reservations_section(contact) # rubocop:disable Metrics/AbcSize
    reservations = Captain::Reservation
                   .where(contact_id: contact.id)
                   .order(check_in_at: :desc)
                   .limit(MAX_RESERVATIONS)
    return '## Reservas\n_(sem reservas registradas)_' if reservations.empty?

    lines = ['## Reservas']
    reservations.each do |r|
      checkin = r.check_in_at&.strftime('%d/%m/%Y às %Hh%M') || '-'
      created = r.created_at.strftime('%d/%m/%Y')
      total = r.total_amount.to_f
      deposit = r.metadata.to_h['deposit_amount'].to_f
      paid = Captain::PixCharge.exists?(reservation_id: r.id, status: 'paid')
      lines << "### Reserva ##{r.id} — check-in #{checkin}"
      lines << "Suíte: #{r.suite_identifier || '-'} · Status: **#{r.status}** · " \
               "Total: R$ #{format('%.2f', total)} · Sinal: R$ #{format('%.2f', deposit)} " \
               "(#{paid ? 'pago' : 'não pago'}) · Criada em #{created}"
    end
    lines.join("\n")
  end

  def conversations_section(contact, query)
    convs = contact.conversations.order(last_activity_at: :desc).limit(MAX_CONVERSATIONS)
    return '## Conversas anteriores\n_(sem conversas registradas)_' if convs.empty?

    lines = ['## Conversas recentes']
    convs.each do |c|
      label_str = c.label_list.any? ? " · labels: #{c.label_list.join(', ')}" : ''
      activity = c.last_activity_at&.strftime('%d/%m/%Y %H:%M') || '-'
      lines << "### Conversa ##{c.display_id} (#{c.status}) — #{activity}#{label_str}"
      msg_lines = sample_messages(c, query)
      lines.concat(msg_lines) if msg_lines.any?
    end
    lines.join("\n")
  end

  def sample_messages(conversation, query)
    scope = conversation.messages
                        .where(message_type: %i[incoming outgoing], private: false)
                        .where('content ~* ?', '\\S')
    scope = scope.where('content ILIKE ?', "%#{query}%") if query.present?
    scope = scope.reorder(created_at: :asc).limit(MAX_MESSAGE_SAMPLES_PER_CONV)

    scope.map do |m|
      who = m.message_type == 'incoming' ? 'Cliente' : 'Atendente'
      preview = m.content.to_s.gsub(/\s+/, ' ').strip[0, 200]
      "- **#{who}:** #{preview}"
    end
  end
end
