# Tira a conversa das mãos da IA e entrega para uma pessoa — e faz o caminho
# inverso quando um humano devolve a conversa para a IA.
#
# .perform é o ÚNICO lugar que define o que "transferir para humano" significa:
#   1. status vira `open` — e é isso que cala a IA, porque
#      Enterprise::MessageTemplates::HookExecutionService só aciona o Captain
#      quando a conversa está `pending`;
#   2. entram as labels `triagem_humana` (guard do OutgoingJob) e `triagem_<motivo>`;
#   3. nasce uma nota interna explicando por que a IA saiu de cena.
#
# Dois caminhos chegam aqui e precisam se comportar igual:
#   - determinístico: o assistente chama a tool MCP `handoff`;
#   - rede de segurança: o callback detecta a frase-âncora "Um momento — vou verificar".
#
# .release é a operação inversa, acionada por Enterprise::Conversation quando o
# status vira `pending` — o jeito do operador dizer "a IA volta a responder".
# Sem isso, mudar o status não bastava: as labels de triagem continuavam lá,
# o guard de Captain::Hermes::OutgoingJob continuava batendo, e a conversa
# ficava muda para sempre (bug real: conv 126 da conta 2, handoff às 14:44,
# devolvida às 15:00, cliente falou às 15:01 e 15:02 em 25/08/2026 e nunca
# mais foi respondido).
#
# Idempotente: chamar de novo numa conversa já em triagem (ou já liberada)
# não duplica nota nem escreve à toa.
class Captain::Hermes::HumanTriageService
  DEFAULT_REASON = 'sem_resposta_segura'.freeze
  TRIAGE_REASON_PREFIX = 'triagem_'.freeze

  def self.perform(conversation:, reason: nil)
    new(conversation: conversation, reason: reason).perform
  end

  def self.release(conversation:)
    new(conversation: conversation).release
  end

  def initialize(conversation:, reason: nil)
    @conversation = conversation
    @reason = reason.presence || DEFAULT_REASON
  end

  def perform
    return false if @conversation.blank?

    already_triaged = @conversation.label_list.include?('triagem_humana')

    @conversation.update!(status: :open) unless @conversation.open?
    @conversation.update_labels(next_labels)
    Captain::Hermes::HumanTriageNoteService.new(conversation: @conversation, reason: @reason).perform unless already_triaged

    Rails.logger.info("[Captain::Hermes::HumanTriage] conv #{@conversation.display_id} → triagem_humana (#{@reason})")
    true
  end

  # Remove só o que .perform (ou o motor antigo) pode ter aplicado: as labels
  # de bloqueio do guard (HUMAN_TRIAGE_LABELS) e as auxiliares `triagem_<motivo>`.
  # Não toca em label nenhuma fora desse vocabulário — `duda_desligada`,
  # `lead_novo`, etc. sobrevivem.
  def release
    return false if @conversation.blank?

    removed = @conversation.label_list.select { |label| triage_label?(label) }
    return false if removed.empty?

    @conversation.update_labels(@conversation.label_list - removed)
    create_release_note(removed)

    Rails.logger.info("[Captain::Hermes::HumanTriage] conv #{@conversation.display_id} ← liberada pra IA (labels removidas: #{removed.join(', ')})")
    true
  end

  private

  def next_labels
    (@conversation.label_list + ['triagem_humana', "#{TRIAGE_REASON_PREFIX}#{@reason}"]).compact_blank.uniq
  end

  def triage_label?(label)
    Captain::Hermes::OutgoingJob::HUMAN_TRIAGE_LABELS.include?(label) || label.start_with?(TRIAGE_REASON_PREFIX)
  end

  def create_release_note(removed_labels)
    @conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @conversation.inbox.captain_assistant,
      content: "🔓 Conversa devolvida para a IA: atendimento humano encerrado, travas de triagem removidas (#{removed_labels.join(', ')}).",
      content_attributes: {
        external_source: 'hermes_human_triage_release'
      }
    )
  end
end
