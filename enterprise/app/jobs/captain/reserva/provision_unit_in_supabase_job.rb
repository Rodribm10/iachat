# frozen_string_literal: true

# Wrapper assíncrono pro ProvisionUnitInSupabaseService.
# Disparado via Captain::Unit#after_commit (criação) e pelo rake de reconciliação.
# Falhas não levantam exception — só logam — pra não bloquear criação da unit.
class Captain::Reserva::ProvisionUnitInSupabaseJob < ApplicationJob
  queue_as :low

  def perform(unit_id)
    unit = Captain::Unit.find_by(id: unit_id)
    return Rails.logger.warn("[ProvisionUnitInSupabaseJob] unit=#{unit_id} não encontrada") if unit.blank?

    result = Captain::Reserva::ProvisionUnitInSupabaseService.new(unit: unit).perform
    return if result[:success]

    Rails.logger.warn(
      "[ProvisionUnitInSupabaseJob] unit=#{unit_id} falhou: #{result[:error]}"
    )
  end
end
