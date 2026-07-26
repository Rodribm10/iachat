# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Inter::CertificadosAlertJob, type: :job do
  let(:resultado_com_alerta) do
    {
      referencia: '2026-06-28T12:00:00Z',
      alerta_dias: 15,
      resumo: {
        total_units: 2,
        expired: 1,
        expiring_soon: 0,
        missing: 1,
        invalid: 0,
        ok: 0,
        alertable: 2
      },
      unidades: [
        {
          unit_id: 2,
          unit_name: 'PrimeAL',
          status: 'vencido',
          not_after: '2026-06-09T21:07:19Z',
          days_until_expiry: -19
        },
        {
          unit_id: 5,
          unit_name: 'Express Aguas Lindas',
          status: 'ausente',
          not_after: nil,
          days_until_expiry: nil
        }
      ]
    }
  end

  let(:resultado_sem_alerta) do
    {
      referencia: '2026-06-28T12:00:00Z',
      alerta_dias: 15,
      resumo: {
        total_units: 1,
        expired: 0,
        expiring_soon: 0,
        missing: 0,
        invalid: 0,
        ok: 1,
        alertable: 0
      },
      unidades: []
    }
  end

  let(:service) { instance_double(Captain::Inter::CertificadosStatusService) }

  around do |example|
    original = ENV.fetch('INTER_CERTIFICATE_ALERT_WEBHOOK_URL', nil)
    example.run
  ensure
    if original.nil?
      ENV.delete('INTER_CERTIFICATE_ALERT_WEBHOOK_URL')
    else
      ENV['INTER_CERTIFICATE_ALERT_WEBHOOK_URL'] = original
    end
    ENV.delete('CEO_DIGEST_MATTERMOST_WEBHOOK_URL')
  end

  before do
    allow(Captain::Inter::CertificadosStatusService).to receive(:new).and_return(service)
  end

  it 'nao envia webhook quando nao ha alerta' do
    ENV['INTER_CERTIFICATE_ALERT_WEBHOOK_URL'] = 'https://mm.example.com/hooks/certs'
    allow(service).to receive(:call).and_return(resultado_sem_alerta)
    allow(HTTParty).to receive(:post)

    described_class.perform_now

    expect(HTTParty).not_to have_received(:post)
  end

  it 'nao envia webhook quando a env nao esta configurada' do
    ENV.delete('INTER_CERTIFICATE_ALERT_WEBHOOK_URL')
    allow(service).to receive(:call).and_return(resultado_com_alerta)
    allow(HTTParty).to receive(:post)

    described_class.perform_now

    expect(HTTParty).not_to have_received(:post)
  end

  it 'envia alerta ao Mattermost quando ha alerta e webhook configurado' do
    ENV['INTER_CERTIFICATE_ALERT_WEBHOOK_URL'] = 'https://mm.example.com/hooks/certs'
    response = instance_double(HTTParty::Response, success?: true)

    allow(service).to receive(:call).and_return(resultado_com_alerta)
    allow(HTTParty).to receive(:post).and_return(response)

    described_class.perform_now

    expect(HTTParty).to have_received(:post).with(
      'https://mm.example.com/hooks/certs',
      hash_including(
        body: include('PrimeAL').and(include('certificado(s) vencido(s)')),
        headers: { 'Content-Type' => 'application/json' },
        timeout: described_class::TIMEOUT_SECONDS
      )
    )
  end

  it 'usa webhook do CEO Digest como fallback' do
    ENV.delete('INTER_CERTIFICATE_ALERT_WEBHOOK_URL')
    ENV['CEO_DIGEST_MATTERMOST_WEBHOOK_URL'] = 'https://mm.example.com/hooks/ceo'
    response = instance_double(HTTParty::Response, success?: true)

    allow(service).to receive(:call).and_return(resultado_com_alerta)
    allow(HTTParty).to receive(:post).and_return(response)

    described_class.perform_now

    expect(HTTParty).to have_received(:post).with(
      'https://mm.example.com/hooks/ceo',
      hash_including(timeout: described_class::TIMEOUT_SECONDS)
    )
  end
end
