# Cria uma cobrança PIX na API do Banco Inter (endpoint /pix/v2/cob).
# Requer certificados mTLS e credenciais configuradas na unidade.
class Captain::Inter::CobService
  API_BASE_URL = 'https://cdpj.partners.bancointer.com.br'.freeze

  def initialize(reservation, amount: nil)
    @reservation = reservation
    @unit = reservation.unit
    @amount = amount
  end

  def call
    raise 'Unit not configured for Pix' if @unit&.inter_pix_key.blank?
    raise 'Missing Inter certificates' unless @unit.inter_credentials_present?

    token = Captain::Inter::AuthService.new(@unit).token
    payload = build_payload

    response = connection(token).post('/pix/v2/cob', payload.to_json)
    safe_body = normalize_text(response.body)
    raise "Pix Creation Failed: #{safe_body}" unless response.success?

    data = JSON.parse(safe_body)

    Rails.logger.info "[BANCO INTER] Pix charge created (txid: #{data['txid']})"

    persist_charge(data)
  end

  private

  def build_payload
    amount = @amount.present? ? @amount.to_f.round(2) : @reservation.total_amount.to_f.round(2)

    {
      calendario: { expiracao: Captain::PixCharge::EXPIRATION_SECONDS },
      devedor: {
        cpf: @reservation.contact.custom_attributes['cpf'] || '00000000000',
        nome: @reservation.contact.name || 'Cliente'
      },
      valor: { original: format('%.2f', amount) },
      chave: @unit.inter_pix_key,
      solicitacaoPagador: "Reserva #{@reservation.id}"
    }
  end

  def persist_charge(data)
    pix_code = data['pixCopiaECola'] ||
               data.dig('pix', 'copiaECola') ||
               data['qrcode'] ||
               data['textoImagemQRcode']

    charge = @unit.pix_charges.create!(
      reservation: @reservation,
      txid: data['txid'],
      pix_copia_e_cola: pix_code,
      status: 'active',
      e2eid: nil,
      raw_webhook_payload: data.to_json
    )

    @reservation.update!(current_pix_charge_id: charge.id)
    charge
  end

  def connection(token)
    Faraday.new(url: API_BASE_URL) do |conn|
      conn.headers['Authorization']    = "Bearer #{token}"
      conn.headers['Content-Type']     = 'application/json'
      conn.headers['x-conta-corrente'] = @unit.inter_account_number

      cert_raw = @unit.inter_cert_content.presence || File.read(@unit.resolved_inter_cert_path.to_s)
      key_raw  = @unit.inter_key_content.presence  || File.read(@unit.resolved_inter_key_path.to_s)

      conn.ssl[:client_cert] = OpenSSL::X509::Certificate.new(cert_raw)
      conn.ssl[:client_key]  = OpenSSL::PKey::RSA.new(key_raw)
      conn.adapter Faraday.default_adapter
    end
  end

  def normalize_text(value)
    value.to_s
         .dup
         .force_encoding(Encoding::UTF_8)
         .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
  rescue StandardError
    value.to_s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
  end
end
