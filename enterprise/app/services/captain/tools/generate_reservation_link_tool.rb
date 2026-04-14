# frozen_string_literal: true

# rubocop:disable Metrics/MethodLength
# Ferramenta que gera um link pré-preenchido da página pública de reserva
# (reserva-1001). A Jasmine invoca isso após coletar os dados do cliente
# em conversa e envia a URL como mensagem outgoing.
class Captain::Tools::GenerateReservationLinkTool < Captain::Tools::BaseTool
  DEFAULT_BASE_URL = 'http://localhost:5180'

  def name
    'generate_reservation_link'
  end

  def description
    <<~DESC.strip
      Gera um link da pagina publica de reserva (Reserva Rede 1001) com os
      dados ja pre-preenchidos. Use esta ferramenta quando ja tiver coletado
      em conversa: marca, unidade, categoria da suite, permanencia,
      data/hora de check-in e ao menos nome + telefone + CPF do cliente.
      Envie o link retornado ao cliente como mensagem outgoing para ele
      revisar e pagar. Todos os parametros sao opcionais - passe o que
      souber, a pagina aceita preenchimento parcial.
    DESC
  end

  def tool_parameters_schema
    {
      type: 'object',
      properties: {
        marca: {
          type: 'string',
          description: 'Nome da marca. Ex: "Hotel 1001 Noites".'
        },
        unidade: {
          type: 'string',
          description: 'Nome da unidade do hotel. Ex: "Hotel 1001 Aguas Lindas".'
        },
        permanencia: {
          type: 'string',
          description: 'Permanencia escolhida. Ex: "3hrs", "4hrs", "Pernoite".'
        },
        categoria: {
          type: 'string',
          description: 'Categoria da suite. Ex: "Standard", "Hidromassagem".'
        },
        checkin_at: {
          type: 'string',
          description: 'Data e horario de check-in em ISO 8601. Ex: "2026-04-14T22:00:00".'
        },
        nome: {
          type: 'string',
          description: 'Nome completo do cliente.'
        },
        telefone: {
          type: 'string',
          description: 'Telefone do cliente (com ou sem DDI).'
        },
        cpf: {
          type: 'string',
          description: 'CPF do cliente (apenas numeros ou com pontuacao).'
        },
        email: {
          type: 'string',
          description: 'Email do cliente (opcional).'
        },
        observacao: {
          type: 'string',
          description: 'Observacao ou preferencia especial do cliente (opcional).'
        }
      }
    }
  end

  def execute(*args, **params)
    actual_params = resolve_params(args, params)
    base = ENV.fetch('RESERVA_1001_BASE_URL', DEFAULT_BASE_URL)
    query = build_query(actual_params)
    url = query.empty? ? base : "#{base}/?#{query}"

    {
      formatted_message: "Pronto! Clique no link para revisar e pagar a entrada via PIX:\n#{url}",
      raw_payload: url,
      success: true
    }
  rescue StandardError => e
    Rails.logger.error("[GenerateReservationLinkTool] falha: #{e.class} - #{e.message}")
    { formatted_message: 'Nao consegui gerar o link agora. Tente novamente em instantes.', success: false }
  end

  private

  def build_query(actual_params)
    mapping = {
      marca: actual_params[:marca],
      unidade: actual_params[:unidade],
      permanencia: actual_params[:permanencia],
      categoria: actual_params[:categoria],
      checkin: actual_params[:checkin_at],
      nome: actual_params[:nome],
      telefone: actual_params[:telefone],
      cpf: actual_params[:cpf],
      email: actual_params[:email],
      obs: actual_params[:observacao]
    }
    cleaned = mapping.compact.reject { |_, v| v.to_s.strip.empty? }
    URI.encode_www_form(cleaned)
  end

  def resolve_params(args, params)
    merged = params.to_h

    args.each do |arg|
      next unless arg.is_a?(Hash)
      next if tool_context_hash?(arg)

      merged = arg.merge(merged)
    end

    merged.with_indifferent_access
  end

  def tool_context_hash?(hash)
    hash.key?(:state) ||
      hash.key?('state') ||
      hash.key?(:context) ||
      hash.key?('context') ||
      hash.key?(:conversation) ||
      hash.key?('conversation')
  end
end
# rubocop:enable Metrics/MethodLength
