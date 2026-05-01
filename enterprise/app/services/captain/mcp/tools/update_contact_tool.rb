# Tool MCP: persiste dados do cliente no Contact do Captain (Chatwoot).
#
# Caso de uso: cliente forneceu nome/CPF/email/telefone na conversa.
# Valentina (ou qualquer agente) chama esta tool ASSIM QUE recebe os dados,
# antes mesmo de tentar gerar Pix. Garante que se o cliente abandonar a
# conversa antes de fechar, os dados ficam persistidos pra próxima
# conversa daquele Contact (visível pelo time humano e pelo Hermes via
# [ctx] na próxima vez).
#
# Validações:
# - name: mínimo 3 chars
# - cpf: exatamente 11 dígitos (formato livre — extrai dígitos)
# - email: regex básico
# - phone: aceita formato livre — não normaliza pra E.164 (Chatwoot já cuida disso ao salvar)
#
# Body wins: campo só é atualizado se passado E válido. Passar string vazia = ignora.
class Captain::Mcp::Tools::UpdateContactTool < Captain::Mcp::Tools::BaseTool
  EMAIL_REGEX = /\A[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\z/

  class << self
    def name
      'update_contact'
    end

    def description
      'Salva dados do cliente no cadastro permanente (nome, CPF, email, telefone, ' \
        'observações). Use assim que receber o dado — antes mesmo de gerar Pix. ' \
        'Garante que próxima conversa do mesmo cliente já vem com [ctx: cpf_ok=true]. ' \
        'Não confirme pro cliente que salvou — é bastidor.'
    end

    def input_schema # rubocop:disable Metrics/MethodLength
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid do [ctx]). Obrigatório.'
          },
          name: {
            type: 'string',
            description: 'Nome completo do cliente (mínimo 3 caracteres). Opcional.'
          },
          cpf: {
            type: 'string',
            description: 'CPF do cliente (qualquer formato com 11 dígitos). Opcional.'
          },
          email: {
            type: 'string',
            description: 'Email do cliente. Opcional.'
          },
          phone: {
            type: 'string',
            description: 'Telefone do cliente (com DDD e país preferencialmente). Opcional.'
          },
          notes: {
            type: 'string',
            description: 'Observação livre sobre o cliente (preferências, alergias, ' \
                         'particularidades). Vai pra custom_attributes.notes. Opcional.'
          }
        },
        required: ['conversation_id']
      }
    end
  end

  def call(args, context:) # rubocop:disable Metrics/AbcSize
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]).') if conversation.blank?

    contact = conversation.contact
    return error_response('Conversa sem contato vinculado.') if contact.blank?

    updates = build_updates(args, contact)
    return text_response('Nada novo pra salvar (campos vazios ou já idênticos).') if updates.empty?

    contact.update!(updates)
    text_response("Contato #{contact.id} atualizado: #{updates.keys.join(', ')}.")
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[Captain::Mcp::UpdateContactTool] validation: #{e.record.errors.full_messages.join(', ')}")
    error_response("Validação falhou: #{e.record.errors.full_messages.join(', ')}.")
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::UpdateContactTool] error: #{e.class}: #{e.message}")
    error_response("Erro ao atualizar contato: #{e.message}")
  end

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  def build_updates(args, contact) # rubocop:disable Metrics/AbcSize
    updates = {}
    name = args['name'].to_s.squish
    updates[:name] = name if name.length >= 3 && name != contact.name.to_s.squish

    email = args['email'].to_s.strip.downcase
    updates[:email] = email if email.match?(EMAIL_REGEX) && email != contact.email.to_s.downcase

    phone = args['phone'].to_s.strip
    updates[:phone_number] = phone if phone.present? && phone.gsub(/\D/, '').length >= 10 && phone != contact.phone_number.to_s

    custom_changes = build_custom_attribute_changes(args, contact)
    updates[:custom_attributes] = contact.custom_attributes.to_h.merge(custom_changes) if custom_changes.any?

    updates
  end

  def build_custom_attribute_changes(args, contact)
    custom_changes = {}
    current = contact.custom_attributes.to_h.with_indifferent_access

    cpf_digits = args['cpf'].to_s.gsub(/\D/, '')
    custom_changes['cpf'] = cpf_digits if cpf_digits.length == 11 && cpf_digits != current[:cpf].to_s

    notes = args['notes'].to_s.strip
    custom_changes['notes'] = notes if notes.present? && notes != current[:notes].to_s

    custom_changes
  end
end
