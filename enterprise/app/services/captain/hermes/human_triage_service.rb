# Tira a conversa das mãos da IA e entrega para uma pessoa.
#
# É o ÚNICO lugar que define o que "transferir para humano" significa:
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
# Idempotente: chamar de novo numa conversa já em triagem não duplica nota.
class Captain::Hermes::HumanTriageService
  DEFAULT_REASON = 'sem_resposta_segura'.freeze

  def self.perform(conversation:, reason: nil)
    new(conversation: conversation, reason: reason).perform
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

  private

  def next_labels
    (@conversation.label_list + ['triagem_humana', "triagem_#{@reason}"]).compact_blank.uniq
  end
end
