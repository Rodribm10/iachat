# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Inter::CertificadosStatusService do
  let(:account) { create(:account) }
  let(:brand) { create(:captain_brand, account: account) }

  def certificado_pem(not_after:)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = SecureRandom.random_number(100_000)
    cert.subject = OpenSSL::X509::Name.parse('/CN=Banco Inter Teste')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = 1.year.ago
    cert.not_after = not_after
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    cert.to_pem
  end

  def criar_unidade(nome:, cert: nil)
    create(
      :captain_unit,
      account: account,
      brand: brand,
      name: nome,
      inter_client_id: 'client-id',
      inter_client_secret: 'client-secret',
      inter_pix_key: SecureRandom.uuid,
      inter_account_number: '123456',
      inter_cert_content: cert,
      inter_key_content: 'key-content'
    )
  end

  around do |example|
    travel_to(Time.zone.parse('2026-06-28 09:00:00')) { example.run }
  end

  it 'classifica certificados vencidos, proximos do vencimento, ok, ausentes e invalidos' do
    vencida = criar_unidade(nome: 'Vencida', cert: certificado_pem(not_after: 2.days.ago))
    breve = criar_unidade(nome: 'Vence breve', cert: certificado_pem(not_after: 10.days.from_now))
    ok = criar_unidade(nome: 'Ok', cert: certificado_pem(not_after: 30.days.from_now))
    ausente = criar_unidade(nome: 'Ausente')
    invalida = criar_unidade(nome: 'Invalida', cert: 'certificado-quebrado')

    resultado = described_class.new(alerta_dias: 15).call
    por_id = resultado[:unidades].index_by { |unit| unit[:unit_id] }

    expect(por_id[vencida.id][:status]).to eq('vencido')
    expect(por_id[breve.id][:status]).to eq('vence_em_breve')
    expect(por_id[ok.id][:status]).to eq('ok')
    expect(por_id[ausente.id][:status]).to eq('ausente')
    expect(por_id[invalida.id][:status]).to eq('invalido')
    expect(resultado[:resumo]).to include(
      expired: 1,
      expiring_soon: 1,
      ok: 1,
      missing: 1,
      invalid: 1,
      alertable: 4
    )
  end
end
