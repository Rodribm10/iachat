# Leva para o CRM quem demonstrou interesse real — e só quem demonstrou.
#
# A regra de negócio já existe e já é aplicada: o SOUL da Duda manda ela
# distinguir ALUNO de LEAD antes de qualquer coisa, e ela registra a decisão
# como etiqueta na conversa. Aluno da academia nunca recebe `lead_novo`,
# `quer_experimental` ou `visita_marcada` — então não vai para o CRM, que é
# exatamente o pedido: cliente novo entra, cliente antigo não.
#
# Por que varredura e não gancho no momento em que a etiqueta é aplicada:
# a etiqueta pode vir da IA (tool `add_label`), de uma pessoa marcando na UI ou
# de uma automação. Um gancho num desses caminhos perderia os outros, e gancho
# perdido em integração vira dado faltando que ninguém percebe. A varredura é
# idempotente e pega os três.
#
# Custo em token: ZERO. Não passa pelo agente — ver a justificativa na
# Captain::Crm::TwentyClient.
class Captain::Crm::SyncLeadsJob < ApplicationJob
  queue_as :scheduled_jobs

  # Ordem = progressão no funil. Quando a conversa tem mais de uma etiqueta,
  # vale a mais avançada: quem marcou visita já passou do "quer experimental".
  STAGE_BY_LABEL = {
    'lead_novo' => 'LEAD_NOVO',
    'quer_experimental' => 'QUER_EXPERIMENTAL',
    'visita_marcada' => 'VISITA_MARCADA',
    'matriculado' => 'MATRICULADO'
  }.freeze

  STAGE_ORDER = STAGE_BY_LABEL.values.freeze

  # Janela de varredura. Generosa de propósito: o custo de reprocessar é uma
  # comparação em memória (nada é enviado quando o estágio não mudou), e o de
  # perder alguém é um lead fora do CRM.
  LOOKBACK = 7.days

  def perform
    return unless Captain::Crm::TwentyClient.configured?

    @stats = Hash.new(0)
    Captain::Crm::TwentyClient.enabled_account_ids.each { |account_id| sync_account(account_id) }
    log_summary
  rescue StandardError => e
    Rails.logger.error("[Captain::Crm::SyncLeads] #{e.class}: #{e.message}")
  end

  private

  def client
    @client ||= Captain::Crm::TwentyClient.new
  end

  def sync_account(account_id)
    account = Account.find_by(id: account_id)
    return if account.blank?

    contacts_with_stage(account).each do |contact, stage|
      sync_contact(contact, stage)
    rescue Captain::Crm::TwentyClient::Error => e
      # Falha em um contato não pode parar a fila inteira.
      @stats[:errors] += 1
      Rails.logger.error("[Captain::Crm::SyncLeads] contato #{contact.id}: #{e.message}")
    end
  end

  # Contato -> estágio mais avançado entre as etiquetas das conversas dele.
  def contacts_with_stage(account)
    conversations = account.conversations
                           .where('conversations.updated_at >= ?', LOOKBACK.ago)
                           .tagged_with(STAGE_BY_LABEL.keys, any: true)
                           .includes(:contact)

    conversations.group_by(&:contact).filter_map do |contact, convs|
      next if contact.blank?

      stage = best_stage(convs)
      next if stage.blank?

      [contact, stage]
    end
  end

  def best_stage(conversations)
    stages = conversations.flat_map { |c| c.label_list.filter_map { |label| STAGE_BY_LABEL[label] } }
    stages.max_by { |stage| STAGE_ORDER.index(stage) || -1 }
  end

  def sync_contact(contact, stage)
    attrs = contact.custom_attributes.to_h
    person_id = attrs['twenty_person_id'].presence

    # Nada mudou desde a última sincronização: não gasta chamada.
    return @stats[:skipped] += 1 if person_id.present? && attrs['twenty_stage'] == stage

    first_name, last_name = split_name(contact.name)

    if person_id.present?
      client.update_person(person_id: person_id, stage: stage)
      @stats[:updated] += 1
    else
      person_id = client.create_person(
        first_name: first_name, last_name: last_name,
        phone: contact.phone_number, stage: stage
      )
      return if person_id.blank?

      @stats[:created] += 1
    end

    contact.update!(custom_attributes: attrs.merge('twenty_person_id' => person_id, 'twenty_stage' => stage))
  end

  def split_name(name)
    parts = name.to_s.strip.split
    return [nil, nil] if parts.empty?

    [parts.first, parts[1..].join(' ').presence]
  end

  def log_summary
    return if @stats.values.sum.zero?

    Rails.logger.info(
      "[Captain::Crm::SyncLeads] criados=#{@stats[:created]} atualizados=#{@stats[:updated]} " \
      "sem_mudanca=#{@stats[:skipped]} erros=#{@stats[:errors]}"
    )
  end
end
