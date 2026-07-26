# Fecha a quarentena das FAQs aprendidas de conversas com triagem humana.
#
# Fase 1: a promoção é por tempo — sobreviveu 30 dias em produção sem ser
# aposentada ou corrigida, vira conhecimento definitivo. A promoção por métrica
# (uso real, re-correção humana, queda de handoff no cluster de intenção)
# depende do attribution e entra na Fase 2.
class Captain::AssistantResponses::ProbationJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    promoted = 0

    Captain::AssistantResponse.trial_expired.find_each do |response|
      response.promote!
      promoted += 1
    rescue StandardError => e
      Rails.logger.error("[Captain::Probation] failed to promote ##{response.id}: #{e.class} #{e.message}")
    end

    Rails.logger.info("[Captain::Probation] promoted #{promoted} responses out of quarantine")
    promoted
  end
end
