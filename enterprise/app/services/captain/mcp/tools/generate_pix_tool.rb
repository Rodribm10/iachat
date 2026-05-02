# Tool MCP: gera cobrança Pix Inter pra reserva de uma suíte.
#
# Caso de uso: cliente confirmou reserva (categoria + dia + duração).
# Hermes invoca esta tool com os dados estruturados; o CAPTAIN calcula o
# valor (consultando Captain::Mcp::PricingTables — fonte de verdade
# backend) e dispara a cobrança Pix via integração Inter já existente.
#
# **NUNCA aceitamos `amount` do LLM** — isso evita que ele invente
# desconto VIP, cortesia ou erro de cálculo. O LLM só fornece os dados
# de classificação; a tabela hardcoded no Captain decide o valor.
#
# Fluxo:
#   1. Resolve Conversation → Inbox → Captain::Unit
#   2. Lookup pricing (Captain::Mcp::PricingTables.calculate)
#   3. Cria/reusa Captain::Reservation (status=draft)
#   4. Captain::Inter::CobService gera Pix (txid + copia-e-cola)
#   5. Posta mensagem outgoing na conversa com link curto do pagamento
#   6. Marca conversa com label `aguardando_pagamento`
#   7. Retorna resumo curto pro LLM (sem URL pra evitar reposta colada)
# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength
class Captain::Mcp::Tools::GeneratePixTool < Captain::Mcp::Tools::BaseTool
  DEFAULT_DEPOSIT_RATIO = 0.5 # sinal padrão = 50% do total
  HOURS_BY_PERIOD = {
    '3h' => 3,
    'pernoite_promo' => 13,    # 21h → 10h
    'pernoite_integral' => 13,
    'diaria' => 24
  }.freeze

  class << self
    def name
      'generate_pix'
    end

    def description
      'Gera cobrança Pix pro sinal da reserva (50% do total). Use quando o cliente ' \
        'confirmou: categoria de suíte, dia/horário, e tem nome+CPF cadastrados. ' \
        'O Captain CALCULA o valor pela tabela oficial — você só passa os dados de ' \
        'classificação, NUNCA o valor. A tool envia o link do Pix direto pro cliente; ' \
        'você só confirma que foi gerado.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid do [ctx]). Obrigatório.'
          },
          suite_category: {
            type: 'string',
            description: 'Categoria da suíte (ex: "suite_master", "apartamento", "mini_chale_45", "chale_2_suites", "suite_ouro", "chale_master_4_suites"). Aceita variações naturais.'
          },
          period: {
            type: 'string',
            enum: %w[3h pernoite_promo pernoite_integral diaria],
            description: 'Tipo de permanência. "pernoite_promo" = Dom-Qui (mais barato). ' \
                         '"pernoite_integral" = Sex/Sáb/Feriado/Véspera (mais caro). "3h" = permanência curta. "diaria" = 24h.'
          },
          total_guests: {
            type: 'integer',
            description: 'Quantidade TOTAL de hóspedes (não só os extras). Default 2 (casal). A taxa de pessoa extra é calculada automaticamente conforme regra da categoria.',
            default: 2
          },
          check_in_date: {
            type: 'string',
            description: 'Data de check-in (YYYY-MM-DD ou DD/MM/YYYY). Default: hoje no fuso da conta.'
          }
        },
        required: %w[conversation_id suite_category period]
      }
    end
  end

  def call(args, context:)
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]) em arguments.') if conversation.blank?

    unit = resolve_unit(conversation, context)
    return error_response('Unidade do Captain não vinculada à inbox dessa conversa.') if unit.blank?
    return error_response('Unidade não tem credenciais Inter configuradas. Avise a gerência.') unless unit.inter_credentials_present?

    contact = conversation.contact
    hydrate_contact_from_recent_messages!(contact, conversation)
    missing = identity_missing_fields(contact)
    return error_response("Faltam dados do cliente pra gerar Pix: #{missing.join(', ')}. Peça ao cliente antes de chamar esta tool.") if missing.any?

    pricing = Captain::Mcp::PricingTables.calculate(
      unit_id: unit.id,
      suite_category: args['suite_category'],
      period: args['period'],
      total_guests: (args['total_guests'] || 2).to_i
    )
    return error_response("Preço não calculado: #{pricing[:error]}") if pricing[:error].present?

    total_amount = pricing[:amount]
    deposit = (total_amount * DEFAULT_DEPOSIT_RATIO).round(2)

    reservation = build_or_update_reservation!(conversation, unit, args, pricing, total_amount, deposit)

    begin
      charge = Captain::Inter::CobService.new(reservation, amount: deposit).call
    rescue StandardError => e
      Rails.logger.error("[Captain::Mcp::GeneratePixTool] Inter falhou — usando fallback: #{e.class}: #{e.message}")
      return dispatch_fallback_link!(conversation, unit, reservation, pricing, total_amount, deposit)
    end

    # Move da fase 'draft' pra 'pending_payment' — agora a reservation
    # aparece nas abas/Kanban "Aguardando PIX" do painel.
    reservation.update!(status: :pending_payment)

    dispatch_link_message(conversation, charge, deposit)
    mark_awaiting_payment(conversation)

    text_response(
      "Pix gerado: sinal R$ #{format('%.2f',
                                     deposit)} (50% de R$ #{format('%.2f',
                                                                   total_amount)} — #{pricing[:breakdown][:suite_category]} / #{pricing[:breakdown][:period]}). Link enviado em mensagem separada na conversa #{conversation.display_id}."
    )
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::GeneratePixTool] error: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    error_response("Erro ao gerar Pix: #{e.message}")
  end

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  # Resolve unit em 3 níveis (defesa em profundidade contra divergência
  # entre Captain::Assistant.captain_unit_id e CaptainInbox.captain_unit_id):
  #   1. Assistant.captain_unit (autoritativo — setado por hermes-provision
  #      e admin UI; não vaza entre agentes que compartilham inbox).
  #   2. CaptainInbox legacy (fallback pré-engine column; só funciona se
  #      a inbox tem 1 agente único).
  #   3. Captain::Unit.inbox_id legacy (fallback antigo, antes de CaptainInbox).
  def resolve_unit(conversation, context = nil)
    asst_id = context && (context[:assistant_id] || context['assistant_id'])
    if asst_id
      asst = Captain::Assistant.find_by(id: asst_id)
      return asst.captain_unit if asst&.captain_unit_id.present?
    end

    captain_inbox = CaptainInbox.find_by(inbox_id: conversation.inbox_id)
    return captain_inbox.captain_unit if captain_inbox&.captain_unit.present?

    Captain::Unit.find_by(account_id: conversation.account_id, inbox_id: conversation.inbox_id)
  end

  def identity_missing_fields(contact)
    missing = []
    missing << 'nome completo' if contact&.name.to_s.squish.length < 3
    cpf_digits = contact&.custom_attributes.to_h.with_indifferent_access[:cpf].to_s.gsub(/\D/, '')
    missing << 'CPF' if cpf_digits.length != 11
    missing
  end

  CPF_REGEX = /\b(\d{3}\.?\d{3}\.?\d{3}-?\d{2}|\d{11})\b/
  NAME_RUN_REGEX = /\A([\p{L}'\-]{3,}(?:\s+[\p{L}'\-]{2,}){1,5})/u

  # Cliente normalmente envia nome+CPF junto numa mensagem ("Rodrigo Borba 12345678901").
  # Quando o contact ainda não tem CPF/nome cadastrados, varremos as últimas
  # 10 mensagens incoming pra extrair e popular antes de chamar a Inter.
  def hydrate_contact_from_recent_messages!(contact, conversation)
    return if contact.blank?

    needs_cpf = contact.custom_attributes.to_h.with_indifferent_access[:cpf].to_s.gsub(/\D/, '').length != 11
    needs_name = contact.name.to_s.squish.length < 3
    return unless needs_cpf || needs_name

    extracted_cpf = nil
    extracted_name = nil

    conversation.messages
                .where(message_type: :incoming, sender_type: 'Contact')
                .reorder(created_at: :desc)
                .limit(10).each do |msg|
      text = msg.content.to_s
      extracted_cpf ||= extract_cpf(text) if needs_cpf
      extracted_name ||= extract_name(text) if needs_name
      break if (!needs_cpf || extracted_cpf) && (!needs_name || extracted_name)
    end

    updates = {}
    updates[:name] = extracted_name if needs_name && extracted_name.present?
    updates[:custom_attributes] = contact.custom_attributes.to_h.merge('cpf' => extracted_cpf) if needs_cpf && extracted_cpf.present?
    return if updates.empty?

    contact.update!(updates)
    Rails.logger.info("[Captain::Mcp::GeneratePixTool] hydrated contact #{contact.id} with #{updates.keys}")
  rescue StandardError => e
    Rails.logger.warn("[Captain::Mcp::GeneratePixTool] hydrate failed: #{e.class} - #{e.message}")
  end

  def extract_cpf(text)
    digits = text.to_s.scan(CPF_REGEX).flatten.first.to_s.gsub(/\D/, '')
    digits.length == 11 ? digits : nil
  end

  # Extrai 2-6 palavras alfabéticas seguidas no início do texto, ignorando
  # números/pontuação ao redor.
  def extract_name(text)
    cleaned = text.to_s.gsub(/[\d.,;:\-()]+/, ' ').squish
    match = cleaned.match(NAME_RUN_REGEX)
    return nil if match.nil?

    candidate = match[1].strip
    return nil if candidate.length < 5

    candidate.split.map(&:capitalize).join(' ')
  end

  # Reusa a draft mais recente da conversa (últimas 2h) ou cria nova.
  # Atualiza campos com base nos novos args (categoria pode ter mudado).
  def build_or_update_reservation!(conversation, unit, args, pricing, total_amount, deposit)
    check_in_at = parse_check_in(args['check_in_date'], conversation.account)
    period_hours = HOURS_BY_PERIOD[pricing[:breakdown][:period]] || 13
    check_out_at = check_in_at + period_hours.hours

    reservation = recent_draft_for(conversation) || Captain::Reservation.new(
      account: conversation.account,
      inbox: conversation.inbox,
      contact: conversation.contact,
      contact_inbox: conversation.contact_inbox,
      conversation: conversation,
      captain_unit_id: unit.id
    )

    reservation.assign_attributes(
      suite_identifier: pricing[:breakdown][:suite_category],
      check_in_at: check_in_at,
      check_out_at: check_out_at,
      status: :draft,
      payment_status: 'pending',
      total_amount: total_amount,
      metadata: (reservation.metadata.to_h).merge(
        'full_amount' => total_amount,
        'deposit_amount' => deposit,
        'created_by' => 'mcp_generate_pix_tool',
        'pricing_breakdown' => pricing[:breakdown].stringify_keys
      )
    )

    reservation.save!
    reservation
  end

  def recent_draft_for(conversation)
    Captain::Reservation
      .where(conversation_id: conversation.id, status: 'draft')
      .where('updated_at > ?', 2.hours.ago)
      .order(updated_at: :desc).first
  end

  def parse_check_in(raw, account)
    tz = account.respond_to?(:timezone) ? (account.timezone.presence || Time.zone.name) : Time.zone.name
    Time.use_zone(tz) do
      base = if raw.blank?
               Time.zone.today
             else
               try_parse_date(raw) || Time.zone.today
             end
      Time.zone.local(base.year, base.month, base.day, 21, 0, 0) # entrada padrão 21h
    end
  end

  def try_parse_date(raw)
    Date.iso8601(raw)
  rescue ArgumentError
    begin
      Date.strptime(raw, '%d/%m/%Y')
    rescue ArgumentError
      nil
    end
  end

  def dispatch_link_message(conversation, charge, deposit)
    base_url = InstallationConfig.find_by(name: 'FRONTEND_URL')&.value.presence ||
               ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    base_url = base_url.gsub('0.0.0.0', '127.0.0.1') if base_url.include?('0.0.0.0')

    token = charge.to_sgid(expires_in: 2.hours, purpose: :pix_payment).to_s
    link  = Rails.application.routes.url_helpers.short_payment_link_url(token, host: base_url)

    body = "💸 *Pix do sinal — R$ #{format('%.2f', deposit)}*\n\n" \
           "Abra o link abaixo pra ver o QR Code e copiar o código Pix:\n#{link}\n\n" \
           'Sua reserva fica confirmada automaticamente assim que o pagamento cair (alguns segundos).'

    Messages::MessageBuilder.new(
      nil,
      conversation,
      content: body,
      message_type: 'outgoing'
    ).perform
  rescue StandardError => e
    Rails.logger.warn("[Captain::Mcp::GeneratePixTool] failed to dispatch link: #{e.class} - #{e.message}")
  end

  def mark_awaiting_payment(conversation)
    current = conversation.label_list
    merged = (current + ['aguardando_pagamento']).uniq - %w[pagamento_confirmado reserva_feita]
    conversation.update_labels(merged)
  end

  # Quando a Inter API falha (auth, certificado, timeout, etc), em vez de
  # devolver erro, mandamos o cliente pra página oficial de reserva
  # (reserva-1001) com query string preenchida. Cliente conclui por lá.
  # Marca a conversa com `pix_falhou_fallback` pra triagem da gerência.
  def dispatch_fallback_link!(conversation, unit, reservation, pricing, total_amount, deposit)
    base = ENV.fetch('RESERVA_1001_BASE_URL',
                     InstallationConfig.find_by(name: 'RESERVA_1001_BASE_URL')&.value.presence ||
                       'https://reservas.hoteis1001noites.com.br')
    contact = conversation.contact
    custom = contact&.custom_attributes.to_h.with_indifferent_access

    params = {
      marca: unit.brand&.name,
      unidade: unit.name,
      permanencia: humanize_period(pricing[:breakdown][:period]),
      categoria: humanize_category(pricing[:breakdown][:suite_category]),
      checkin: reservation.check_in_at&.iso8601,
      nome: contact&.name,
      telefone: contact&.phone_number,
      cpf: custom[:cpf],
      email: contact&.email
    }.compact.reject { |_, v| v.to_s.strip.empty? }

    url = "#{base.chomp('/')}/?#{URI.encode_www_form(params)}"

    body = 'Tive um problema técnico pra gerar o Pix por aqui — mas tudo certo, é só finalizar pela página oficial ' \
           "(seus dados já estão pré-preenchidos):\n#{url}"

    Messages::MessageBuilder.new(nil, conversation, content: body, message_type: 'outgoing').perform

    current = conversation.label_list
    conversation.update_labels((current + %w[aguardando_pagamento pix_falhou_fallback]).uniq)

    text_response(
      "Inter API indisponível. Link da página de reserva enviado pro cliente (R$ #{format('%.2f',
                                                                                          total_amount)} total / R$ #{format('%.2f',
                                                                                                                             deposit)} sinal). Marquei conversa com pix_falhou_fallback."
    )
  end

  PERIOD_LABELS = {
    '3h' => '3hrs',
    'pernoite_promo' => 'Pernoite',
    'pernoite_integral' => 'Pernoite',
    'diaria' => 'Diaria'
  }.freeze

  def humanize_period(period_key)
    PERIOD_LABELS[period_key] || period_key.to_s.humanize
  end

  CATEGORY_LABELS = {
    'apartamento' => 'Apartamento',
    'suite_master' => 'Suite Master',
    'suite_luxo' => 'Suite Luxo',
    'suite_tematica' => 'Suite Tematica',
    'mini_chale_45' => 'Mini Chale 45',
    'chale_2_suites' => 'Chale 2 Suites',
    'suite_ouro' => 'Suite Ouro',
    'chale_master_4_suites' => 'Chale Master 4 Suites'
  }.freeze

  def humanize_category(cat_key)
    CATEGORY_LABELS[cat_key] || cat_key.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength
