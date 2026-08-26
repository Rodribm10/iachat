# Cliente REST do Twenty CRM (self-hosted).
#
# Por que REST e não o MCP do Twenty: gravar lead é trabalho mecânico e de
# volume — não precisa de julgamento. Passar isso pelo agente custaria ~1.074
# tokens por turno só nas definições das ferramentas (medido em 26/08/2026),
# mais 3 idas e voltas por gravação, porque o MCP do Twenty usa padrão de
# catálogo (get_tool_catalog → learn_tools → execute_tool) e cada ida reenvia o
# histórico inteiro da conversa. Com ~165 mensagens/dia na academia isso é caro
# e não compra nada: quem decide se a pessoa é lead já é a Duda, e ela já
# registra a decisão na etiqueta. Aqui só transportamos o que ela decidiu.
class Captain::Crm::TwentyClient
  TIMEOUT_SECONDS = 15

  class Error < StandardError; end

  def self.configured?
    base_url.present? && api_key.present?
  end

  def self.base_url
    ENV.fetch('TWENTY_CRM_BASE_URL', nil).presence&.chomp('/')
  end

  def self.api_key
    ENV.fetch('TWENTY_CRM_API_KEY', nil).presence
  end

  # Contas habilitadas. Vazio = integração desligada — a ausência da env é o
  # jeito de manter isto inerte nas instalações que não usam CRM.
  def self.enabled_account_ids
    ENV.fetch('TWENTY_CRM_ACCOUNT_IDS', '').split(',').filter_map { |id| id.strip.presence&.to_i }
  end

  def create_person(first_name:, last_name:, phone: nil, stage: nil)
    body = person_payload(first_name: first_name, last_name: last_name, phone: phone, stage: stage)
    body[:createdBy] = { source: 'API' }

    response = post('/rest/people', body)
    response.dig('data', 'createPerson', 'id')
  end

  def update_person(person_id:, stage: nil, first_name: nil, last_name: nil, phone: nil)
    body = person_payload(first_name: first_name, last_name: last_name, phone: phone, stage: stage)
    return nil if body.blank?

    patch("/rest/people/#{person_id}", body)
    person_id
  end

  private

  def person_payload(first_name:, last_name:, phone:, stage:)
    body = {}
    name = { firstName: first_name, lastName: last_name }.compact_blank
    body[:name] = name if name.present?
    body[:estagio] = stage if stage.present?

    # O Twenty guarda telefone em três partes. O Chatwoot entrega E.164
    # (+5561...), então separamos o DDI do resto; sem isso o CRM mostra o
    # número com o +55 grudado e a busca por telefone não casa.
    if phone.present?
      digits = phone.to_s.gsub(/\D/, '')
      national = digits.start_with?('55') ? digits[2..] : digits
      body[:phones] = {
        primaryPhoneNumber: national,
        primaryPhoneCallingCode: '+55',
        primaryPhoneCountryCode: 'BR'
      }
    end

    body
  end

  def post(path, body)
    request(:post, path, body)
  end

  def patch(path, body)
    request(:patch, path, body)
  end

  def request(method, path, body)
    response = HTTParty.send(
      method,
      "#{self.class.base_url}#{path}",
      body: body.to_json,
      headers: {
        'Authorization' => "Bearer #{self.class.api_key}",
        'Content-Type' => 'application/json'
      },
      timeout: TIMEOUT_SECONDS
    )
    raise Error, "Twenty respondeu HTTP #{response.code}: #{response.body.to_s.truncate(200)}" unless response.success?

    response.parsed_response
  rescue HTTParty::Error, Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED => e
    raise Error, "Erro de rede falando com o Twenty (#{e.class}): #{e.message}"
  end
end
