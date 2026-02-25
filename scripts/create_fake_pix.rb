#!/usr/bin/env ruby
# frozen_string_literal: true

# Cria PIX fake para testar webhook

unit = Captain::Unit.find_by(name: 'Samambaia')
inbox = Inbox.first
account = inbox.account

# Busca ou cria contato
contact = inbox.contacts.first
unless contact
  contact = Contact.create!(account: account, name: 'Teste Cliente', email: 'teste@example.com')
  ContactInbox.create!(contact: contact, inbox: inbox)
end

conversation = Conversation.create!(
  account: account,
  inbox: inbox,
  contact: contact,
  status: 'open'
)

reservation = Captain::Reservation.create!(
  conversation_id: conversation.id,
  unit: unit,
  captain_brand_id: unit.captain_brand_id,
  total_amount: 100.00,
  status: 'pending_payment'
)

charge = Captain::PixCharge.create!(
  reservation: reservation,
  unit: unit,
  txid: "TEST#{SecureRandom.hex(8)}",
  pix_copia_e_cola: '00020101021226930014BR.GOV.BCB.PIX...',
  status: 'active'
)

puts '✅ PIX de teste criado!'
puts "   TxID: #{charge.txid}"
puts "   Reserva ID: #{reservation.id}"
puts "   Conversa ID: #{conversation.id}"
puts "   Valor: R$ #{charge.original_value}"
puts "\n🚀 Agora execute: bundle exec rails runner scripts/test_inter_webhook.rb"
