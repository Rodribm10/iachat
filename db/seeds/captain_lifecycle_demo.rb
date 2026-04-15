# db/seeds/captain_lifecycle_demo.rb
# Run with: bundle exec rails runner db/seeds/captain_lifecycle_demo.rb
#
# Creates a demo rule + reservation and leaves the delivery scheduled
# so the engineer can inspect it, fast-forward, or trigger manually.

account = Account.first || raise('No Account exists; create one first')
unit = account.captain_units.first || raise('No Captain::Unit exists; create one first')
inbox = unit.inboxes.first || raise('Unit has no inboxes')

# Ensure unit has concierge config
unit.update!(
  concierge_inbox_id: inbox.id,
  concierge_config: {
    'persona_name' => 'Sofia',
    'knowledge' => "## Sobre\nHotel exemplo para teste de lifecycle.\n## Wifi\nSenha: demo123\n",
    'variables' => { 'wifi_password' => 'demo123' }
  }
)

rule = Captain::Lifecycle::Rule.create!(
  account: account,
  name: 'DEMO lembrete 10min antes check-in',
  enabled: true,
  event: 'checkin.scheduled_at',
  offset_minutes: -10,
  filters: {},
  message_type: 'text',
  message_body: 'Oi {{ customer.first_name }}! Sua {{ reservation.suite }} tá pronta. Wifi: {{ hotel.wifi_password }}'
)

contact = account.contacts.find_or_create_by!(phone_number: '+5561900000000') do |c|
  c.name = 'Cliente Demo'
  c.email = 'demo@example.com'
end

reservation = Captain::Reservation.create!(
  account: account,
  unit: unit,
  contact: contact,
  suite_identifier: 'Alexa',
  status: :scheduled,
  total_amount: 160.0,
  check_in_at: 30.minutes.from_now,
  check_out_at: 8.hours.from_now,
  inbox: inbox,
  metadata: { 'permanencia' => 'Pernoite' }
)

delivery = Captain::Lifecycle::Delivery.where(captain_reservation_id: reservation.id).last

# rubocop:disable Rails/Output
puts '--- DEMO CREATED ---'
puts "Rule:        #{rule.id} — #{rule.name}"
puts "Reservation: #{reservation.id} (check_in_at = #{reservation.check_in_at})"
puts "Delivery:    #{delivery&.id} status=#{delivery&.status} fire_at=#{delivery&.fire_at}"
puts
puts 'To fire now:'
puts "  Captain::Lifecycle::DispatcherJob.perform_now(#{delivery&.id})"
# rubocop:enable Rails/Output
