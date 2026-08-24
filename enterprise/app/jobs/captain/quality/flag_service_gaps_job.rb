# Marca automaticamente falhas de atendimento: cliente sem resposta, demora
# crítica pra primeira resposta útil, e objeção de preço ignorada. Roda a
# cada 15 minutos (config/schedule.yml). Só etiqueta — nunca envia mensagem.
#
# Por que existe: medido na conta 2 (academia Zelo/Dom Bosco, 24/08/2026),
# 6 de 25 conversas do dia tinham falha clara — cliente esperando
# trancamento desde 14:51, lead que ouviu o preço e respondeu "Obrigada,
# não gostei" sem receber mais nada, aluno que esperou 5h e recebeu de
# volta só "Olá boa tarde tudo bem?" sem resposta à pergunta. 98% das
# respostas humanas saem direto pelo WhatsApp (fora do Chatwoot), então
# ninguém vê fila nem quem está esperando — as etiquetas tornam isso
# visível e medível.
#
# `cliente_aguardando` e `demora_critica` leem `conversations.waiting_since`
# (coluna indexada que o Chatwoot já zera em toda resposta não-privada ou
# bot, e na resolução — ver Message#update_waiting_since e
# Conversation#handle_resolved_status_change) e por isso se AUTO-REMOVEM
# assim que alguém responde. `objecao_sem_resposta` é diferente por design:
# uma vez marcada, NUNCA é removida por este job — é registro histórico
# pro relatório (uma objeção ignorada não deixa de ter acontecido só
# porque, horas depois, alguém respondeu).
class Captain::Quality::FlagServiceGapsJob < ApplicationJob
  queue_as :scheduled_jobs

  LABEL_WAITING = 'cliente_aguardando'.freeze
  LABEL_CRITICAL = 'demora_critica'.freeze
  LABEL_OBJECTION = 'objecao_sem_resposta'.freeze

  WAITING_THRESHOLD = 30.minutes
  CRITICAL_THRESHOLD = 2.hours
  ACTIVITY_LOOKBACK = 48.hours
  OPEN_STATUSES = %w[open pending].freeze

  # Começo deliberadamente conservador (só objeção de preço/orçamento em
  # português) e fácil de estender: acrescente a forma já minúscula e sem
  # acento — o matcher transliteta a mensagem do cliente do mesmo jeito
  # antes de comparar, então "não" e "nao" já batem com a entrada "nao".
  OBJECTION_PATTERNS = [
    'nao gostei',
    'ta caro',
    'muito caro',
    'achei caro',
    'caro demais',
    'fora do meu orcamento',
    'nao tenho condicoes',
    'vou pensar',
    'vou ver',
    'depois eu vejo'
  ].freeze

  def perform
    @stats = Hash.new(0)

    inbox_ids_by_account.each do |account_id, inbox_ids|
      process_account(account_id, inbox_ids)
    end

    log_summary
  rescue StandardError => e
    Rails.logger.error("[Captain::Quality::FlagServiceGaps] #{e.class}: #{e.message}")
  end

  private

  # Só contas com pelo menos uma inbox conectada a um Captain::Assistant
  # (captain_interno ou hermes) — evita varredura global em conta sem
  # atendimento automatizado (trial parado, conta de teste etc).
  def inbox_ids_by_account
    CaptainInbox.joins(:inbox)
                .pluck(:inbox_id, 'inboxes.account_id')
                .group_by(&:last)
                .transform_values { |rows| rows.map(&:first) }
  end

  def process_account(account_id, inbox_ids)
    whatsapp_phones = whatsapp_phone_by_inbox(inbox_ids)

    conversations_scope(account_id, inbox_ids).find_each do |conversation|
      next if self_conversation?(conversation, whatsapp_phones)

      sync_labels!(conversation)
    end
  end

  def conversations_scope(account_id, inbox_ids)
    Conversation.where(account_id: account_id, inbox_id: inbox_ids, status: OPEN_STATUSES)
                .where('last_activity_at >= ?', ACTIVITY_LOOKBACK.ago)
                .includes(:contact)
  end

  # Contato criado pelo @lid do WhatsApp ecoando o próprio número do canal
  # (a academia "conversando com ela mesma") — não é cliente real. Mesmo
  # problema tratado, do lado da consolidação de contato, em
  # app/services/whatsapp/contact_inbox_consolidation_service.rb.
  def self_conversation?(conversation, whatsapp_phones)
    channel_phone = whatsapp_phones[conversation.inbox_id]
    return false if channel_phone.blank?

    contact_phone = conversation.contact&.phone_number
    return false if contact_phone.blank?

    normalize_phone(contact_phone) == normalize_phone(channel_phone)
  end

  def normalize_phone(value)
    value.to_s.gsub(/\D/, '')
  end

  def whatsapp_phone_by_inbox(inbox_ids)
    Channel::Whatsapp.joins(:inbox)
                     .where(inboxes: { id: inbox_ids })
                     .pluck('inboxes.id', 'channel_whatsapp.phone_number')
                     .to_h
  end

  # Lê o label_list UMA vez, decide o estado alvo num array Ruby comum e
  # grava UMA vez no fim. Importante: `Conversation#add_labels` (Labelable)
  # recalcula a partir da associação `labels` (tags), que não reflete um
  # `update!` anterior no MESMO objeto em memória — chamar add_labels duas
  # vezes seguidas no mesmo `conversation` PERDE a primeira etiqueta. Por
  # isso todo o cálculo abaixo fica em array puro, e só a gravação final
  # toca o Rails/acts-as-taggable-on.
  def sync_labels!(conversation)
    original = conversation.label_list.to_a
    labels = original.dup

    toggle(labels, LABEL_WAITING, waiting_at_least?(conversation, WAITING_THRESHOLD))
    toggle(labels, LABEL_CRITICAL, waiting_at_least?(conversation, CRITICAL_THRESHOLD))
    add_objection_label(labels, conversation)

    return if labels == original

    (labels - original).each do |label|
      ensure_account_label!(conversation.account_id, label)
      @stats["#{label}_added"] += 1
    end
    (original - labels).each { |label| @stats["#{label}_removed"] += 1 }
    conversation.update!(label_list: labels)
  end

  def waiting_at_least?(conversation, threshold)
    conversation.waiting_since.present? && conversation.waiting_since <= threshold.ago
  end

  def toggle(labels, label, should_have_label)
    if should_have_label
      labels << label unless labels.include?(label)
    else
      labels.delete(label)
    end
  end

  # Diferente de toggle: uma vez presente, esta etiqueta nunca é removida
  # nem reavaliada por este job (ver comentário no topo do arquivo) — só
  # entra no array, nunca sai.
  def add_objection_label(labels, conversation)
    return if labels.include?(LABEL_OBJECTION)

    last_customer_message = last_customer_message_for(conversation)
    return unless last_customer_message
    return unless objection?(last_customer_message.content)
    return if replied_after?(conversation, last_customer_message.created_at)

    labels << LABEL_OBJECTION
  end

  def last_customer_message_for(conversation)
    conversation.messages
                .where(message_type: :incoming, private: false)
                .where.not(content: [nil, ''])
                .reorder(created_at: :desc)
                .first
  end

  def replied_after?(conversation, since)
    conversation.messages
                .where(message_type: :outgoing, private: false)
                .where('created_at > ?', since)
                .reorder(nil)
                .exists?
  end

  def objection?(content)
    normalized = ActiveSupport::Inflector.transliterate(content.to_s.downcase)
    OBJECTION_PATTERNS.any? { |pattern| normalized.include?(pattern) }
  end

  # Registro oficial em `labels` (account_id, title) — sem isso a tag some
  # do sidebar/dropdown da UI. Mesma abordagem de
  # Captain::Mcp::Tools::AddLabelTool#ensure_account_label!.
  def ensure_account_label!(account_id, title)
    return if Label.exists?(account_id: account_id, title: title)

    Label.create!(
      account_id: account_id,
      title: title,
      description: 'Criada automaticamente por Captain::Quality::FlagServiceGapsJob',
      color: '#5C7CFA',
      show_on_sidebar: true
    )
  end

  def log_summary
    return if @stats.empty?

    Rails.logger.info("[Captain::Quality::FlagServiceGaps] #{@stats.sort.to_h}")
  end
end
