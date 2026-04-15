# rubocop:disable RSpec/AnyInstance
require 'rails_helper'

RSpec.describe Captain::Lifecycle::Dispatcher do
  subject(:dispatcher) { described_class.new(delivery) }

  let(:account) { create(:account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:unit) { Captain::Unit.create!(account: account, brand: brand, name: 'Test', concierge_inbox_id: inbox.id) }
  let(:contact) { create(:contact, account: account, name: 'João Silva', phone_number: '+5561999999999') }
  let(:reservation) do
    create(:captain_reservation,
           account: account, unit: unit, contact: contact,
           suite_identifier: 'Alexa',
           check_in_at: 2.hours.from_now, check_out_at: 10.hours.from_now)
  end
  let(:rule) do
    create(:captain_lifecycle_rule,
           account: account, event: 'checkin.scheduled_at', offset_minutes: -10,
           message_body: 'Oi {{ customer.first_name }}, suíte {{ reservation.suite }}!')
  end
  let(:delivery) do
    create(:captain_lifecycle_delivery,
           account: account, captain_reservation: reservation,
           lifecycle_rule: rule, inbox: inbox, fire_at: 1.hour.from_now)
  end

  describe '#call' do
    context 'when all guards pass (happy path)' do
      before do
        real_conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
        real_msg = create(:message, account: account, inbox: inbox, conversation: real_conversation)
        allow_any_instance_of(described_class)
          .to receive(:send_message).and_return(real_msg)
      end

      it 'renders the template and marks delivery sent' do
        dispatcher.call
        expect(delivery.reload.status).to eq('sent')
        expect(delivery.rendered_body).to include('João')
        expect(delivery.rendered_body).to include('Alexa')
      end
    end

    context 'when guard blocks with skip' do
      before { reservation.update!(status: 'cancelled') }

      it 'marks delivery skipped with reason' do
        dispatcher.call
        expect(delivery.reload.status).to eq('skipped')
        expect(delivery.skip_reason).to eq('reservation_cancelled')
      end
    end

    context 'when guard blocks with reschedule' do
      it 'reschedules the delivery and does not send' do
        new_time = 2.hours.from_now
        allow_any_instance_of(Captain::Lifecycle::Guards::QuietHours)
          .to receive(:check).and_return(action: :reschedule, fire_at: new_time)

        expect(Captain::Lifecycle::DispatcherJob).to receive(:perform_at)
        dispatcher.call
        expect(delivery.reload.status).to eq('scheduled')
        expect(delivery.fire_at).to be_within(1.minute).of(new_time)
      end
    end

    context 'when delivery is not in scheduled state' do
      before { delivery.update!(status: 'cancelled') }

      it 'aborts without side effects' do
        dispatcher.call
        expect(delivery.reload.status).to eq('cancelled')
      end
    end
  end
end
# rubocop:enable RSpec/AnyInstance
