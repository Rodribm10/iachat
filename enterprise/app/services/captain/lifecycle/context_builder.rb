# frozen_string_literal: true

class Captain::Lifecycle::ContextBuilder
  def self.build(reservation)
    new(reservation).build
  end

  def initialize(reservation)
    @reservation = reservation
    @contact = reservation.contact
    @unit = reservation.unit
  end

  def build
    {
      'customer' => customer_context,
      'reservation' => reservation_context,
      'hotel' => hotel_context
    }
  end

  private

  def customer_context
    name = @contact&.name.to_s
    {
      'name' => name,
      'first_name' => name.split.first.to_s,
      'phone' => @contact&.phone_number.to_s,
      'cpf' => @contact&.custom_attributes.to_h['cpf'].to_s
    }
  end

  def reservation_context
    {
      'suite' => @reservation.suite_identifier.to_s,
      'unit_name' => @unit&.name.to_s,
      'check_in_at' => format_datetime(@reservation.check_in_at),
      'check_out_at' => format_datetime(@reservation.check_out_at),
      'amount' => format_money(@reservation.total_amount),
      'permanencia' => @reservation.metadata.to_h['permanencia'].to_s
    }
  end

  def hotel_context
    (@unit&.concierge_variables || {}).stringify_keys
  end

  def format_datetime(value)
    return '' unless value

    value.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y %H:%M')
  end

  def format_money(value)
    ActiveSupport::NumberHelper.number_to_currency(
      value.to_f,
      unit: 'R$ ',
      separator: ',',
      delimiter: '.'
    )
  end
end
