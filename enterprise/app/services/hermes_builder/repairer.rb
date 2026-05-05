# Reparos automatizados pra checks FAIL/WARN identificados pelo Validator.
#
# Cada `repair_id` presente em Validator::Result mapeia pra um handler aqui.
# Reparos cobrem só estado em DB (Captain::Assistant, CaptainInbox, Inbox,
# config). Reparos de filesystem/systemd ficam pro CLI hermes-provision na
# VPS — UI mostra mensagem orientadora pro admin.
class HermesBuilder::Repairer
  REPAIR_HANDLERS = %w[
    set_engine_hermes
    sync_captain_inbox_unit
    set_default_typing_delay
    set_default_response_delay
  ].freeze

  def self.repair(slug:, repair_id:)
    asst = ::Captain::Assistant.find_by(hermes_profile_name: slug, engine: 'hermes')
    return failure("Assistant '#{slug}' não encontrado") if asst.nil?
    return failure("Reparo '#{repair_id}' não suportado pela UI. Rode hermes-provision na VPS.") unless REPAIR_HANDLERS.include?(repair_id)

    send("repair_#{repair_id}", asst)
  rescue StandardError => e
    Rails.logger.error("[HermesBuilder::Repairer] error: #{e.class}: #{e.message}")
    failure("Erro: #{e.class}: #{e.message}")
  end

  class << self
    private

    # rubocop:disable Rails/SkipsModelValidations
    def repair_set_engine_hermes(asst)
      asst.update_columns(engine: 'hermes')
      success("Engine setado pra 'hermes' no assistant #{asst.id}")
    end
    # rubocop:enable Rails/SkipsModelValidations

    # Resincroniza CaptainInbox.captain_unit_id com Assistant.captain_unit_id.
    # Esse foi o bug raiz que travou a Juliana — CaptainInbox apontava pra
    # unit antiga (Dolce Amore) enquanto Assistant.captain_unit_id era a
    # nova (Qnn01). Resolve_unit usa CaptainInbox como segundo nível e
    # vazava unit errada quando o context['assistant_id'] não chegava.
    # rubocop:disable Rails/SkipsModelValidations
    def repair_sync_captain_inbox_unit(asst)
      return failure('Assistant sem captain_unit_id setado — corrija primeiro pelo cadastro') if asst.captain_unit_id.blank?

      ci = ::CaptainInbox.where(captain_assistant_id: asst.id).first
      return failure('Sem CaptainInbox pra esse assistant — vincule no painel de inboxes primeiro') if ci.nil?

      old = ci.captain_unit_id
      ci.update_columns(captain_unit_id: asst.captain_unit_id)

      ::Captain::Unit.where(inbox_id: ci.inbox_id).where.not(id: asst.captain_unit_id).update_all(inbox_id: nil)
      ::Captain::Unit.where(id: asst.captain_unit_id).update_all(inbox_id: ci.inbox_id)

      success("CaptainInbox.unit_id ressincronizado: #{old} → #{asst.captain_unit_id}")
    end
    # rubocop:enable Rails/SkipsModelValidations

    def repair_set_default_typing_delay(asst)
      ci = ::CaptainInbox.where(captain_assistant_id: asst.id).first
      return failure('Sem inbox vinculada') if ci&.inbox.nil?

      ci.inbox.update!(typing_delay: 5)
      success("Inbox #{ci.inbox.id} typing_delay setado pra 5s")
    end

    def repair_set_default_response_delay(asst)
      cfg = asst.config.to_h.merge(
        'response_delay' => {
          'mode' => 'typing_simulation',
          'chars_per_second' => 25,
          'min_seconds' => 1.5,
          'max_seconds' => 6.0
        }
      )
      asst.update!(config: cfg)
      success('Humanização typing_simulation ativada (default: 25 cps, 1.5s..6s)')
    end

    def success(msg)
      { ok: true, message: msg }
    end

    def failure(msg)
      { ok: false, error: msg }
    end
  end
end
