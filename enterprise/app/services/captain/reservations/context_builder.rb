# frozen_string_literal: true

# Monta o bloco de contexto da reserva usado na interpolação de prompt dos
# agentes (ver Concerns::Agentable#resolve_reservation_context).
#
# Herdado de Captain::Lifecycle::ContextBuilder, que morreu junto com o
# subsistema de lifecycle em 22/08/2026 — ele nunca teve regra nem entrega em
# produção, mas esta parte era consumida fora dele. O formato dos campos foi
# preservado tal e qual para não mexer nos prompts em uso.
class Captain::Reservations::ContextBuilder
  TIMEZONE = 'America/Sao_Paulo'

  def self.build(reservation)
    new(reservation).build
  end

  def initialize(reservation)
    @reservation = reservation
  end

  def build
    {
      'suite' => @reservation.suite_identifier.to_s,
      'unit_name' => @reservation.unit&.name.to_s,
      'check_in_at' => format_datetime(@reservation.check_in_at),
      'check_out_at' => format_datetime(@reservation.check_out_at),
      'amount' => format_money(@reservation.total_amount),
      'permanencia' => @reservation.metadata.to_h['permanencia'].to_s
    }
  end

  private

  def format_datetime(value)
    return '' unless value

    value.in_time_zone(TIMEZONE).strftime('%d/%m/%Y %H:%M')
  end

  def format_money(value)
    ActiveSupport::NumberHelper.number_to_currency(
      value.to_f, unit: 'R$ ', separator: ',', delimiter: '.'
    )
  end
end
