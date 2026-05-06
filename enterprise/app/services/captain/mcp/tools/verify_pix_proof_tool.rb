# Tool MCP: valida comprovante PIX (modo manual estático).
#
# Caso de uso: unidade opera em pix_mode='manual_static' (Padova, Express).
# Cliente recebeu chave PIX fixa, pagou, e enviou comprovante (imagem).
# Esta tool extrai dados via vision (gpt-5.3-codex multimodal), compara com
# o esperado (valor exato, data ≤24h, beneficiário/chave/banco fuzzy match
# com Captain::Unit.manual_pix_*) e retorna verdict pro Hermes.
#
# Verdicts:
#   - ok                  → tudo bate, chamar confirmar_reserva_pix_manual
#   - duvida              → algo não bate, chamar marcar_reserva_pendente
#   - nao_eh_comprovante  → imagem não é comprovante PIX, pedir reenvio
#
# Hermes, ANTES de chamar esta tool, deve responder ao cliente:
#   "⏳ Só um momento, vou verificar."
# Essa frase aciona handoff humano automaticamente (label triagem_humana),
# de modo que humano sempre acompanhe o resultado da validação.
# rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength
class Captain::Mcp::Tools::VerifyPixProofTool < Captain::Mcp::Tools::BaseTool
  PROOF_FRESHNESS_HOURS = 24
  VALUE_TOLERANCE = 0.0 # zero — valor exato

  class << self
    def name
      'verificar_comprovante_pix'
    end

    def description
      'Valida comprovante PIX (modo manual). Use SOMENTE quando cliente enviar IMAGEM ' \
        'de comprovante numa conversa que tem PIX manual ativo (provider=manual). Extrai dados ' \
        'via vision e compara com a cobrança esperada. Retorna ok / duvida / nao_eh_comprovante. ' \
        'ANTES de chamar, RESPONDA ao cliente "⏳ Só um momento, vou verificar." pra acionar handoff humano.'
    end

    def input_schema
      {
        type: 'object',
        properties: {
          image_url: {
            type: 'string',
            description: 'URL pública da imagem do comprovante (vinda do anexo da mensagem incoming).'
          },
          conversation_id: {
            type: 'integer',
            description: 'ID interno da conversa (cid do [ctx]). Obrigatório.'
          },
          pix_charge_id: {
            type: 'integer',
            description: 'Opcional. ID da Captain::PixCharge associada. Se vazio, usa a charge manual mais recente da conversa.'
          }
        },
        required: %w[image_url conversation_id]
      }
    end
  end

  def call(args, context:)
    conversation = resolve_conversation(args, context)
    return error_response('Conversa não encontrada. Passe conversation_id (cid do [ctx]).') if conversation.blank?

    charge = resolve_charge(conversation, args['pix_charge_id'])
    return error_response('Não há PIX manual aguardando comprovante nesta conversa. Confirme com o cliente o que foi enviado.') if charge.blank?

    unit = charge.unit
    return error_response('PixCharge sem unidade vinculada — não consigo validar o beneficiário esperado.') if unit.blank?

    image_url = args['image_url'].to_s.strip
    return error_response('image_url vazio — passe a URL da imagem do comprovante.') if image_url.blank?

    extracted = extract_proof_via_vision(image_url)
    return text_response_for_verdict(charge, 'nao_eh_comprovante', extracted: extracted, mismatches: ['eh_comprovante_pix=false']) unless extracted['eh_comprovante_pix']

    mismatches = compare_proof(extracted, charge, unit)
    verdict = mismatches.empty? ? 'ok' : 'duvida'

    text_response_for_verdict(charge, verdict, extracted: extracted, mismatches: mismatches)
  rescue StandardError => e
    Rails.logger.error("[Captain::Mcp::VerifyPixProofTool] error: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
    error_response("Erro ao validar comprovante: #{e.message}")
  end

  private

  def resolve_conversation(args, context)
    conv_id = args['conversation_id'].presence ||
              context[:conversation_internal_id] ||
              context[:conversation_id]
    return nil if conv_id.blank?

    Conversation.find_by(id: conv_id) || Conversation.find_by(display_id: conv_id)
  end

  def resolve_charge(conversation, charge_id)
    if charge_id.present?
      charge = Captain::PixCharge.find_by(id: charge_id)
      return charge if charge&.manual?
    end

    Captain::PixCharge.manual.joins(:reservation)
                      .where(captain_reservations: { conversation_id: conversation.id })
                      .where(status: %w[awaiting_proof active])
                      .order(created_at: :desc).first
  end

  def extract_proof_via_vision(image_url)
    parts = [
      { type: 'text', text: vision_prompt },
      { type: 'image_url', image_url: { url: image_url } }
    ]
    content = RubyLLM::Content::Raw.new(parts)

    raw = RubyLLM.chat(model: vision_model)
                 .with_temperature(0)
                 .with_params(response_format: { type: 'json_object' })
                 .ask(content)
                 .content.to_s

    JSON.parse(raw)
  rescue JSON::ParserError => e
    Rails.logger.warn("[Captain::Mcp::VerifyPixProofTool] JSON parse falhou: #{e.message} — raw=#{raw&.first(200)}")
    { 'eh_comprovante_pix' => false, 'parse_error' => true }
  end

  def vision_model
    InstallationConfig.find_by(name: 'CAPTAIN_VISION_MODEL')&.value.presence ||
      ENV.fetch('CAPTAIN_VISION_MODEL', 'gpt-5.3-codex')
  end

  def vision_prompt
    <<~PROMPT
      Você analisa comprovantes de PIX. Receba a imagem e extraia os dados em JSON ESTRITO (sem markdown, sem texto fora do JSON).

      Schema obrigatório:
      {
        "eh_comprovante_pix": boolean,           // true se a imagem é claramente um comprovante de PIX (transferência), false se é qualquer outra coisa (selfie, foto de chave, screenshot de chat, comprovante de outro tipo, etc).
        "valor": number | null,                   // valor transferido em reais (ex: 90.00). Sem cifrão, sem espaços, com ponto decimal.
        "data_hora_iso": string | null,           // data e hora da transação em ISO 8601 com timezone Brasília (-03:00) ou UTC. Ex: "2026-05-06T14:30:00-03:00". Se a imagem só mostrar data sem hora, use 12:00:00.
        "beneficiario_nome": string | null,       // nome do destinatário (quem recebeu). Pode ser nome de empresa, CPF/CNPJ formatado, etc. Texto literal extraído.
        "beneficiario_chave": string | null,      // chave PIX do destinatário se aparecer (CPF, CNPJ, email, telefone, ou chave aleatória UUID). Pode estar em qualquer formato. Texto literal.
        "banco_destino": string | null,           // banco destinatário (ex: "Stone", "Itaú", "Inter"). Texto literal.
        "id_transacao": string | null,            // ID/E2E/autenticação da transação (qualquer identificador único da transação que aparecer).
        "remetente_nome": string | null,          // nome de quem PAGOU (origem). Pode ajudar humano a auditar.
        "suspeitas": [string]                     // lista vazia ou avisos: "imagem_borrada", "edicao_aparente", "fonte_inconsistente", "screenshot_de_screenshot", "valor_ilegivel", etc. SÓ liste suspeitas REAIS, não invente.
      }

      Regras:
      - Retorne APENAS o JSON. Sem prefixo, sem sufixo, sem ```json.
      - Se algum campo não estiver na imagem, use null (não invente).
      - Para valor: sempre número (90.00, não "R$ 90,00").
      - Se a imagem não for claramente um comprovante PIX, eh_comprovante_pix=false e os outros campos podem ser null.
    PROMPT
  end

  def compare_proof(extracted, charge, unit)
    mismatches = []

    expected_value = charge.original_value.to_f
    actual_value = extracted['valor'].to_f
    if expected_value <= 0
      mismatches << 'valor_esperado_indisponivel'
    elsif (actual_value - expected_value).abs > VALUE_TOLERANCE
      mismatches << "valor_divergente (esperado=R$ #{format('%.2f', expected_value)}, comprovante=R$ #{format('%.2f', actual_value)})"
    end

    if extracted['data_hora_iso'].blank?
      mismatches << 'data_ausente_no_comprovante'
    else
      parsed = parse_proof_time(extracted['data_hora_iso'])
      if parsed.nil?
        mismatches << "data_invalida (#{extracted['data_hora_iso']})"
      elsif parsed > 1.hour.from_now
        mismatches << "data_no_futuro (#{extracted['data_hora_iso']})"
      elsif parsed < PROOF_FRESHNESS_HOURS.hours.ago
        mismatches << "data_antiga (#{extracted['data_hora_iso']}, > #{PROOF_FRESHNESS_HOURS}h)"
      end
    end

    expected_owner = unit.manual_pix_owner_name.to_s
    actual_owner = extracted['beneficiario_nome'].to_s
    mismatches << "beneficiario_divergente (esperado='#{expected_owner}', comprovante='#{actual_owner}')" unless name_matches?(expected_owner, actual_owner)

    expected_key = normalize_pix_key(unit.manual_pix_key)
    actual_key = normalize_pix_key(extracted['beneficiario_chave'])
    if expected_key.present? && actual_key.present? && !key_matches?(expected_key, actual_key)
      mismatches << "chave_divergente (esperada=#{unit.manual_pix_key}, comprovante=#{extracted['beneficiario_chave']})"
    end

    expected_bank = unit.manual_pix_bank_name.to_s.downcase
    actual_bank = extracted['banco_destino'].to_s.downcase
    if expected_bank.present? && actual_bank.present? && !bank_matches?(expected_bank, actual_bank)
      mismatches << "banco_divergente (esperado='#{unit.manual_pix_bank_name}', comprovante='#{extracted['banco_destino']}')"
    end

    suspeitas = Array(extracted['suspeitas']).reject(&:blank?)
    mismatches << "suspeitas_vision: #{suspeitas.join(', ')}" if suspeitas.any?

    mismatches
  end

  # Match flexível pra nome do beneficiário: case-insensitive, sem
  # acentos, ignora pontuação e múltiplos espaços. Considera match se
  # uma string contém a outra OU se compartilham >= 70% das palavras
  # significativas (>2 chars).
  def name_matches?(expected, actual)
    return false if expected.blank? || actual.blank?

    e = normalize_text(expected)
    a = normalize_text(actual)
    return true if e == a
    return true if a.include?(e) || e.include?(a)

    e_words = e.split.select { |w| w.length > 2 }
    a_words = a.split.select { |w| w.length > 2 }
    return false if e_words.empty?

    matched = e_words.count { |w| a_words.any? { |aw| aw.include?(w) || w.include?(aw) } }
    (matched.to_f / e_words.size) >= 0.7
  end

  def key_matches?(expected, actual)
    return true if expected == actual

    expected.include?(actual) || actual.include?(expected)
  end

  def bank_matches?(expected, actual)
    actual.include?(expected) || expected.include?(actual)
  end

  def normalize_pix_key(key)
    key.to_s.downcase.gsub(/[^\w@.+-]/, '')
  end

  def normalize_text(text)
    text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
        .downcase.gsub(/[^a-z0-9\s]/, ' ').squish
  end

  def parse_proof_time(raw)
    Time.iso8601(raw)
  rescue ArgumentError, TypeError
    begin
      Time.zone.parse(raw)
    rescue ArgumentError
      nil
    end
  end

  def text_response_for_verdict(charge, verdict, extracted:, mismatches:)
    payload = {
      verdict: verdict,
      charge_id: charge.id,
      reservation_id: charge.reservation_id,
      expected: {
        valor: charge.original_value.to_f,
        beneficiario: charge.unit.manual_pix_owner_name,
        chave: charge.unit.manual_pix_key,
        banco: charge.unit.manual_pix_bank_name
      },
      extracted: extracted.slice('valor', 'data_hora_iso', 'beneficiario_nome', 'beneficiario_chave', 'banco_destino', 'id_transacao', 'remetente_nome'),
      mismatches: mismatches
    }

    persist_extraction!(charge, extracted, mismatches, verdict)

    text_response("VERIFICACAO_COMPROVANTE\n#{JSON.pretty_generate(payload)}\n\n" \
                  "Próximo passo:\n" \
                  "- ok                → criar_nota_interna(...) + confirmar_reserva_pix_manual(pix_charge_id=#{charge.id})\n" \
                  "- duvida            → criar_nota_interna(...) + marcar_reserva_pendente(pix_charge_id=#{charge.id}, motivo=...)\n" \
                  '- nao_eh_comprovante → peça novamente o comprovante real (sem handoff, sem nota interna).')
  end

  def persist_extraction!(charge, extracted, mismatches, verdict)
    payload = {
      'verdict' => verdict,
      'extracted' => extracted,
      'mismatches' => mismatches,
      'verified_at' => Time.current.iso8601
    }
    # rubocop:disable Rails/SkipsModelValidations
    # Skip de validação proposital — payload é JSON livre, não tem
    # validação no model. Update direto evita disparar callbacks (ex:
    # post_internal_pix_sent_note iria postar nota duplicada).
    charge.update_columns(manual_proof_payload: payload)
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[Captain::Mcp::VerifyPixProofTool] persist failed: #{e.class} - #{e.message}")
  end
end
# rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Layout/LineLength
