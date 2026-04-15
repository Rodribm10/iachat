# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Guards::CustomerReplied do
  subject(:guard) { described_class.new(delivery) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:reservation) { create(:captain_reservation, account: account, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: inbox) }
  let(:delivery) do
    d = create(:captain_lifecycle_delivery,
               account: account, captain_reservation: reservation,
               inbox: inbox,
               fire_at: 1.minute.from_now)
    d.update!(conversation_id: conversation.id)
    d
  end

  context 'when guard is disabled' do
    before { create(:captain_lifecycle_config, account: account, pause_on_customer_reply: false) }

    it 'passes' do
      expect(guard.check).to eq(action: :pass)
    end
  end

  context 'when guard is enabled with 60 min window' do
    before do
      create(:captain_lifecycle_config,
             account: account, pause_on_customer_reply: true, pause_on_customer_reply_within_minutes: 60)
    end

    it 'passes when no incoming messages exist' do
      expect(guard.check).to eq(action: :pass)
    end

    it 'reschedules when customer sent a message 10min ago' do
      create(:message,
             account: account, conversation: conversation, inbox: inbox,
             message_type: 'incoming', content: 'Olá', sender: contact,
             created_at: 10.minutes.ago)

      result = guard.check
      expect(result[:action]).to eq(:reschedule)
      expect(result[:fire_at]).to be_within(1.minute).of(10.minutes.ago + 60.minutes)
    end

    it 'passes when the only messages are outgoing' do
      agent = create(:user, account: account)
      create(:message,
             account: account, conversation: conversation, inbox: inbox,
             message_type: 'outgoing', content: 'Respondendo', sender: agent,
             created_at: 5.minutes.ago)

      expect(guard.check).to eq(action: :pass)
    end

    it 'skips too_stale when customer replied more than 2h + window ago' do
      # fire_at = 1 min from now; last_incoming = 3h ago; wait_until = 3h ago + 60min = 2h ago
      # wait_until < fire_at → pass
      create(:message,
             account: account, conversation: conversation, inbox: inbox,
             message_type: 'incoming', content: 'Mensagem antiga', sender: contact,
             created_at: 3.hours.ago)

      expect(guard.check).to eq(action: :pass)
    end

    it 'skips too_stale when delay exceeds MAX_DELAY' do
      past_delivery = create(:captain_lifecycle_delivery,
                             account: account, captain_reservation: reservation,
                             inbox: inbox,
                             fire_at: 3.hours.ago)
      past_delivery.update!(conversation_id: conversation.id)
      past_guard = described_class.new(past_delivery)

      # last incoming = 10min ago; window = 60min; wait_until = 50min from now
      # fire_at = 3h ago; delay = wait_until - fire_at ≈ 3h50m > 2h → too_stale
      create(:message,
             account: account, conversation: conversation, inbox: inbox,
             message_type: 'incoming', content: 'Mensagem recente', sender: contact,
             created_at: 10.minutes.ago)

      result = past_guard.check
      expect(result[:action]).to eq(:skip)
      expect(result[:reason]).to eq('too_stale')
    end
  end

  context 'when delivery has no conversation but delivery has inbox_id' do
    subject(:guard_no_conv) { described_class.new(delivery_without_conv) }

    before do
      create(:captain_lifecycle_config,
             account: account, pause_on_customer_reply: true, pause_on_customer_reply_within_minutes: 60)
    end

    let(:delivery_without_conv) do
      create(:captain_lifecycle_delivery,
             account: account, captain_reservation: reservation,
             inbox: inbox,
             fire_at: 1.minute.from_now)
    end

    it 'resolves conversation via inbox and contact' do
      create(:message,
             account: account, conversation: conversation, inbox: inbox,
             message_type: 'incoming', content: 'Hey', sender: contact,
             created_at: 5.minutes.ago)

      result = guard_no_conv.check
      expect(result[:action]).to eq(:reschedule)
    end
  end
end
