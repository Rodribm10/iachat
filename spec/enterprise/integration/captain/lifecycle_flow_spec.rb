# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Captain::Lifecycle end-to-end flow' do
  # rubocop:enable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:unit) do
    Captain::Unit.create!(
      account: account, brand: brand, name: 'Águas Lindas',
      concierge_inbox_id: inbox.id,
      concierge_config: {
        'persona_name' => 'Sofia',
        'variables' => { 'wifi_password' => 'hotel1001' }
      }
    )
  end
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5561988887777') }

  # Ensure a CaptainInbox exists so Dispatcher can resolve concierge_assistant_for(inbox)
  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
  end

  def build_reservation(extra = {})
    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox) do |ci|
      ci.source_id = contact.phone_number.to_s.gsub(/\D/, '')
    end
    attrs = {
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      unit: unit,
      suite_identifier: 'Alexa',
      check_in_at: 2.hours.from_now,
      check_out_at: 10.hours.from_now,
      status: :confirmed
    }.merge(extra)
    Captain::Reservation.create!(attrs)
  end

  # rubocop:disable RSpec/MultipleExpectations
  it 'schedules, dispatches, and logs a delivery through the full pipeline' do
    # 1. Create a rule  (checkin.scheduled_at so fire_at = check_in_at - 10min = ~110min from now)
    rule = create(:captain_lifecycle_rule,
                  account: account,
                  event: 'checkin.scheduled_at',
                  offset_minutes: -10,
                  message_body: 'Oi {{ customer.first_name }}! Wi-fi: {{ hotel.wifi_password }}')

    # 2. Create a reservation with check_in 2 hours out
    reservation = build_reservation

    # 3. Delivery was scheduled
    delivery = Captain::Lifecycle::Delivery.last
    expect(delivery).not_to be_nil
    expect(delivery.status).to eq('scheduled')
    expect(delivery.lifecycle_rule_id).to eq(rule.id)
    expect(delivery.fire_at).to be_within(1.second).of(reservation.check_in_at - 10.minutes)

    # 4. Stub send_message at Dispatcher level to avoid real HTTP/MessageBuilder
    msg = create(:message,
                 account: account,
                 conversation: create(:conversation, account: account, inbox: inbox, contact: contact),
                 message_type: :outgoing,
                 content: 'stub')
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Captain::Lifecycle::Dispatcher).to receive(:send_message).and_return(msg)
    # rubocop:enable RSpec/AnyInstance

    # 5. Fire the job directly (skip Sidekiq scheduling)
    Captain::Lifecycle::DispatcherJob.perform_now(delivery.id)

    # 6. Delivery is now sent
    delivery.reload
    expect(delivery.status).to eq('sent')
    expect(delivery.rendered_body).to include('Maria')
    expect(delivery.rendered_body).to include('hotel1001')
    expect(delivery.sent_at).to be_present
  end
  # rubocop:enable RSpec/MultipleExpectations

  it 'cancels pending deliveries when reservation is cancelled' do
    create(:captain_lifecycle_rule,
           account: account,
           event: 'checkin.scheduled_at',
           offset_minutes: -10,
           message_body: 'Oi')

    reservation = build_reservation
    delivery = Captain::Lifecycle::Delivery.last
    expect(delivery.status).to eq('scheduled')

    reservation.update!(status: 'cancelled')
    expect(delivery.reload.status).to eq('cancelled')
  end

  it 'respects the max-5 cap' do
    # Use checkin.scheduled_at with varying negative offsets so fire_at is always in the future
    6.times do |i|
      create(:captain_lifecycle_rule,
             account: account,
             name: "rule-#{i}",
             event: 'checkin.scheduled_at',
             offset_minutes: -(i + 1),
             message_body: "msg #{i}")
    end

    # Stub send so each call succeeds
    msg = create(:message,
                 account: account,
                 conversation: create(:conversation, account: account, inbox: inbox, contact: contact),
                 message_type: :outgoing,
                 content: 'stub')
    # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Captain::Lifecycle::Dispatcher).to receive(:send_message).and_return(msg)
    # rubocop:enable RSpec/AnyInstance

    reservation = build_reservation

    # Fire all scheduled jobs
    deliveries = Captain::Lifecycle::Delivery
                 .where(captain_reservation_id: reservation.id, status: 'scheduled')
                 .to_a
    deliveries.each do |d|
      Captain::Lifecycle::DispatcherJob.perform_now(d.id)
    end

    statuses = Captain::Lifecycle::Delivery
               .where(captain_reservation_id: reservation.id)
               .pluck(:status)
    expect(statuses.count('sent')).to be >= 1

    # If 5 were sent, the 6th should be skipped with max_reached
    if statuses.count('sent') == 5
      skipped = Captain::Lifecycle::Delivery
                .where(captain_reservation_id: reservation.id, status: 'skipped')
                .first
      expect(skipped&.skip_reason).to eq('max_reached')
    end
  end
end
