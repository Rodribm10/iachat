require 'faraday'

# Consulta uma cobrança PIX no Banco Inter (endpoint /pix/v2/cob/{txid}).
# Útil como fallback quando o cliente informa pagamento e o webhook ainda não chegou.
class Captain::Inter::CobStatusService
  API_BASE_URL = 'https://cdpj.partners.bancointer.com.br'.freeze
  PAID_STATUSES = %w[CONCLUIDA].freeze

  def initialize(pix_charge)
    @pix_charge = pix_charge
    @unit = pix_charge.unit
  end

  def call
    raise 'Cobrança Pix inválida para consulta' if @pix_charge.blank?
    raise 'Cobrança Pix sem txid' if @pix_charge.txid.blank?
    raise 'Unit not configured for Pix' if @unit&.inter_pix_key.blank?
    raise 'Missing Inter certificates' unless @unit.inter_credentials_present?

    token = Captain::Inter::AuthService.new(@unit).token
    response = connection(token).get(cob_path)
    safe_body = normalize_text(response.body)

    raise "Pix Status Check Failed: HTTP #{response.status} - #{safe_body}" unless response.success?

    payload = JSON.parse(safe_body)
    parse_payload(payload)
  end

  private

  def cob_path
    encoded_txid = ERB::Util.url_encode(@pix_charge.txid.to_s)
    "/pix/v2/cob/#{encoded_txid}"
  end

  def parse_payload(payload)
    status = payload['status'].to_s.upcase
    pix_items = Array(payload['pix'])
    pix_paid_entry = pix_items.find { |item| item['endToEndId'].present? } || pix_items.first

    paid = PAID_STATUSES.include?(status) || pix_paid_entry.present?

    {
      success: true,
      txid: payload['txid'].presence || @pix_charge.txid,
      status: status,
      paid: paid,
      end_to_end_id: pix_paid_entry&.[]('endToEndId'),
      paid_value: pix_paid_entry&.[]('valor'),
      raw_payload: payload
    }
  end

  def connection(token)
    Faraday.new(url: API_BASE_URL) do |conn|
      apply_headers(conn, token)
      apply_mtls(conn)
      conn.adapter Faraday.default_adapter
    end
  end

  def apply_headers(conn, token)
    conn.headers['Authorization'] = "Bearer #{token}"
    conn.headers['Content-Type'] = 'application/json'
    conn.headers['x-conta-corrente'] = @unit.inter_account_number if @unit.inter_account_number.present?
  end

  def apply_mtls(conn)
    cert_raw, key_raw = cert_material
    conn.ssl[:client_cert] = OpenSSL::X509::Certificate.new(cert_raw)
    conn.ssl[:client_key] = OpenSSL::PKey::RSA.new(key_raw)
  end

  def cert_material
    cert_raw = @unit.inter_cert_content.presence || File.read(@unit.resolved_inter_cert_path.to_s)
    key_raw = @unit.inter_key_content.presence || File.read(@unit.resolved_inter_key_path.to_s)
    [cert_raw, key_raw]
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
