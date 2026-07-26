# frozen_string_literal: true

# Saúde das conexões externas de que o Captain depende.
#
# Nasceu de uma falha real: a credencial Codex venceu em 2026-06-26 e a captura
# de FAQ ficou CINCO SEMANAS morta sem ninguém perceber. O sintoma não era um
# erro visível — era um número que ninguém olhava.
#
# Por isso aqui existem dois tipos de verificação, e o segundo é o que importa:
#
#   1. ESTADO da credencial — barata, mas mente. No dia da falha a data de
#      validade dizia "vencida" enquanto outros caminhos de IA seguiam
#      funcionando; e o contrário também acontece (credencial válida, capacidade
#      quebrada por outro motivo).
#   2. RESULTADO da capacidade — o que o sistema efetivamente produziu na
#      janela. É o único sinal que teria pego a falha real.
#
# Regra herdada do OS Foco: dado ausente é `indisponivel`, nunca `ok`.
class Captain::Health::ConexoesService
  STATUS_ALERTAVEIS = %w[critico alerta indisponivel].freeze

  CODEX_ALERTA_HORAS = 48
  APRENDIZADO_JANELA = 7.days
  HERMES_TIMEOUT = 2

  def initialize(referencia: Time.current)
    @referencia = referencia
  end

  def call
    conexoes = [codex, aprendizado_captain, hermes_agents, certificados_inter]

    {
      referencia: @referencia.iso8601,
      resumo: resumo(conexoes),
      conexoes: conexoes
    }
  end

  private

  attr_reader :referencia

  # --- 1. Credencial do Codex (estado) ---------------------------------------
  def codex
    cred = Captain::CodexCredential.current

    if cred.blank?
      return conexao('codex', 'IA do Captain (Codex OAuth)', 'critico',
                     'Nenhuma credencial ativa. A IA não responde.',
                     acao: 'rails captain:codex:login')
    end

    horas = ((cred.expires_at - referencia) / 1.hour).floor
    if horas.negative?
      conexao('codex', 'IA do Captain (Codex OAuth)', 'critico',
              "Credencial vencida há #{horas.abs}h (#{cred.email})", acao: 'rails captain:codex:login')
    elsif horas <= CODEX_ALERTA_HORAS
      conexao('codex', 'IA do Captain (Codex OAuth)', 'alerta',
              "Vence em #{horas}h. Refresh automático deve renovar; se falhar, reautenticar.")
    else
      conexao('codex', 'IA do Captain (Codex OAuth)', 'ok',
              "Válida por mais #{(horas / 24.0).round(1)} dias (#{cred.email})")
    end
  rescue StandardError => e
    indisponivel('codex', 'IA do Captain (Codex OAuth)', e)
  end

  # --- 2. O aprendizado está de fato acontecendo? (resultado) -----------------
  # Este é o cheque que teria pego a falha de cinco semanas.
  def aprendizado_captain
    desde = referencia - APRENDIZADO_JANELA
    aprendidas = faqs_aprendidas_desde(desde)
    materia_prima = conversas_elegiveis_desde(desde)

    if materia_prima.zero?
      conexao('aprendizado', 'Captura de conhecimento', 'indisponivel',
              'Sem conversas com resposta humana na janela — nada a concluir')
    elsif aprendidas.zero?
      conexao('aprendizado', 'Captura de conhecimento', 'critico',
              "Nada aprendido apesar de #{materia_prima} conversas elegíveis. " \
              'A geração de FAQ está quebrada (credencial de IA é a causa mais comum).',
              acao: 'rails captain:conexoes para ver qual conexão caiu')
    else
      conexao('aprendizado', 'Captura de conhecimento', 'ok',
              "#{aprendidas} FAQs aprendidas de #{materia_prima} conversas elegíveis")
    end
  rescue StandardError => e
    indisponivel('aprendizado', 'Captura de conhecimento', e)
  end

  def faqs_aprendidas_desde(desde)
    Captain::AssistantResponse.where(documentable_type: 'Conversation').where(created_at: desde..).count
  end

  def conversas_elegiveis_desde(desde)
    Conversation.where(status: :resolved).where.not(first_reply_created_at: nil).where(updated_at: desde..).count
  end

  # --- 3. Agentes Hermes alcançáveis? ----------------------------------------
  def hermes_agents
    destinos = Captain::Assistant.hermes.filter_map { |a| destino_hermes(a) }.uniq
    return conexao('hermes', 'Agentes Hermes', 'indisponivel', 'Nenhuma atendente Hermes configurada') if destinos.empty?

    inalcancaveis = destinos.reject { |host, porta| porta_aberta?(host, porta) }

    if inalcancaveis.empty?
      conexao('hermes', 'Agentes Hermes', 'ok', "#{destinos.size} destino(s) respondendo")
    else
      lista = inalcancaveis.map { |h, p| "#{h}:#{p}" }.join(', ')
      conexao('hermes', 'Agentes Hermes', 'critico',
              "#{inalcancaveis.size} de #{destinos.size} destino(s) fora do ar: #{lista}. " \
              'As atendentes desses destinos não conseguem responder.')
    end
  rescue StandardError => e
    indisponivel('hermes', 'Agentes Hermes', e)
  end

  def destino_hermes(assistant)
    base = assistant.hermes_webhook_base_url.presence
    return nil if base.blank?

    uri = URI.parse(base)
    porta = assistant.try(:hermes_port).presence || uri.port
    return nil if uri.host.blank? || porta.blank?

    [uri.host, porta.to_i]
  rescue URI::InvalidURIError
    nil
  end

  def porta_aberta?(host, porta)
    Socket.tcp(host, porta, connect_timeout: HERMES_TIMEOUT, &:close)
    true
  rescue StandardError
    false
  end

  # --- 4. Certificados do Inter (reusa o serviço que já existe) --------------
  def certificados_inter
    status = Captain::Inter::CertificadosStatusService.new(referencia: referencia).call
    alertaveis = status.dig(:resumo, :alertable).to_i

    if alertaveis.zero?
      conexao('inter', 'Certificados Inter (PIX)', 'ok',
              "#{status.dig(:resumo, :ok)} unidade(s) com certificado válido")
    else
      conexao('inter', 'Certificados Inter (PIX)', 'critico',
              "#{alertaveis} unidade(s) com certificado vencido, ausente ou inválido — PIX pode falhar")
    end
  rescue StandardError => e
    indisponivel('inter', 'Certificados Inter (PIX)', e)
  end

  # --- helpers ---------------------------------------------------------------
  def conexao(chave, nome, status, detalhe, acao: nil)
    { chave: chave, nome: nome, status: status, detalhe: detalhe, acao: acao,
      verificado_em: referencia.iso8601 }
  end

  def indisponivel(chave, nome, error)
    conexao(chave, nome, 'indisponivel', "Não foi possível verificar: #{error.class}: #{error.message.to_s[0, 160]}")
  end

  def resumo(conexoes)
    {
      total: conexoes.size,
      ok: conexoes.count { |c| c[:status] == 'ok' },
      alerta: conexoes.count { |c| c[:status] == 'alerta' },
      critico: conexoes.count { |c| c[:status] == 'critico' },
      indisponivel: conexoes.count { |c| c[:status] == 'indisponivel' },
      alertaveis: conexoes.count { |c| STATUS_ALERTAVEIS.include?(c[:status]) }
    }
  end
end
