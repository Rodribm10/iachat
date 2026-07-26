# frozen_string_literal: true

class Captain::Inter::CertificadosStatusService
  ALERTA_PADRAO_DIAS = 15
  STATUS_ALERTAVEIS = %w[vencido vence_em_breve ausente invalido].freeze

  def initialize(referencia: Time.current, alerta_dias: ALERTA_PADRAO_DIAS)
    @referencia = referencia
    @alerta_dias = alerta_dias
  end

  def call
    unidades = Captain::Unit.order(:id).map { |unit| status_da_unidade(unit) }

    {
      referencia: @referencia.iso8601,
      alerta_dias: @alerta_dias,
      resumo: resumo(unidades),
      unidades: unidades
    }
  end

  private

  def status_da_unidade(unit)
    cert = carregar_certificado(unit)
    return status_ausente(unit) if cert.blank?

    vence_em = cert.not_after
    dias_ate_vencer = ((vence_em - @referencia) / 1.day).floor

    {
      unit_id: unit.id,
      unit_name: unit.name,
      account_id: unit.account_id,
      status: status_por_validade(vence_em, dias_ate_vencer),
      cert_present: true,
      credentials_present: unit.inter_credentials_present?,
      pix_key_present: unit.inter_pix_key.present?,
      inter_account_present: unit.inter_account_number.present?,
      not_after: vence_em.iso8601,
      days_until_expiry: dias_ate_vencer
    }
  rescue StandardError => e
    status_invalido(unit, e)
  end

  def carregar_certificado(unit)
    return OpenSSL::X509::Certificate.new(unit.inter_cert_content) if unit.inter_cert_content.present?

    path = unit.resolved_inter_cert_path
    return nil if path.blank? || !File.exist?(path)

    OpenSSL::X509::Certificate.new(File.read(path))
  end

  def status_por_validade(vence_em, dias_ate_vencer)
    return 'vencido' if vence_em < @referencia
    return 'vence_em_breve' if dias_ate_vencer <= @alerta_dias

    'ok'
  end

  def status_ausente(unit)
    {
      unit_id: unit.id,
      unit_name: unit.name,
      account_id: unit.account_id,
      status: 'ausente',
      cert_present: false,
      credentials_present: unit.inter_credentials_present?,
      pix_key_present: unit.inter_pix_key.present?,
      inter_account_present: unit.inter_account_number.present?,
      not_after: nil,
      days_until_expiry: nil
    }
  end

  def status_invalido(unit, error)
    {
      unit_id: unit.id,
      unit_name: unit.name,
      account_id: unit.account_id,
      status: 'invalido',
      cert_present: true,
      credentials_present: unit.inter_credentials_present?,
      error_class: error.class.name,
      error_message: error.message
    }
  end

  def resumo(unidades)
    {
      total_units: unidades.size,
      expired: unidades.count { |u| u[:status] == 'vencido' },
      expiring_soon: unidades.count { |u| u[:status] == 'vence_em_breve' },
      missing: unidades.count { |u| u[:status] == 'ausente' },
      invalid: unidades.count { |u| u[:status] == 'invalido' },
      ok: unidades.count { |u| u[:status] == 'ok' },
      alertable: unidades.count { |u| STATUS_ALERTAVEIS.include?(u[:status]) }
    }
  end
end
