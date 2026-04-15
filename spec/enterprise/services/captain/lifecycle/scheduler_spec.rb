# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::Scheduler do
  let(:account) { create(:account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:unit) { Captain::Unit.create!(account: account, brand: brand, name: 'Test Unit') }
  let(:reservation) do
    create(:captain_reservation,
           account: account,
           unit: unit,
           check_in_at: 2.hours.from_now,
           check_out_at: 10.hours.from_now)
  end

  describe '.schedule_for' do
    # Reservation must be created BEFORE rules so the after_create_commit
    # :schedule_lifecycle_rules hook finds nothing and doesn't auto-create deliveries.
    before { reservation }

    let!(:matching_rule) do
      create(:captain_lifecycle_rule,
             account: account,
             event: 'checkin.scheduled_at',
             offset_minutes: -10)
    end

    it 'creates a scheduled delivery for each matching enabled rule' do
      expect { described_class.schedule_for(reservation) }
        .to change(Captain::Lifecycle::Delivery, :count).by(1)
    end

    it 'sets fire_at to event_time + offset' do
      described_class.schedule_for(reservation)
      delivery = Captain::Lifecycle::Delivery.last
      expect(delivery.fire_at).to be_within(1.second).of(reservation.check_in_at - 10.minutes)
    end

    it 'enqueues a Sidekiq job for fire_at' do
      expect(Captain::Lifecycle::DispatcherJob).to receive(:perform_at)
        .with(kind_of(Time), kind_of(Integer))
      described_class.schedule_for(reservation)
    end

    it 'skips disabled rules' do
      matching_rule.update!(enabled: false)
      expect { described_class.schedule_for(reservation) }
        .not_to change(Captain::Lifecycle::Delivery, :count)
    end

    it 'skips rules where filter does not match' do
      matching_rule.update!(filters: { 'categorias' => ['DoesNotExist'] })
      expect { described_class.schedule_for(reservation) }
        .not_to change(Captain::Lifecycle::Delivery, :count)
    end
  end

  describe '.cancel_pending' do
    let!(:delivery) do
      create(:captain_lifecycle_delivery,
             account: account,
             captain_reservation: reservation,
             status: 'scheduled')
    end
    let!(:sent) do
      create(:captain_lifecycle_delivery,
             account: account,
             captain_reservation: reservation,
             status: 'sent')
    end

    it 'marks scheduled deliveries as cancelled' do
      described_class.cancel_pending(reservation)
      expect(delivery.reload.status).to eq('cancelled')
    end

    it 'does not touch sent deliveries' do
      described_class.cancel_pending(reservation)
      expect(sent.reload.status).to eq('sent')
    end
  end

  describe '.reschedule_for_checkin_change' do
    let!(:checkin_rule) do
      create(:captain_lifecycle_rule,
             account: account,
             event: 'checkin.scheduled_at',
             offset_minutes: -10)
    end

    before do
      create(:captain_lifecycle_rule,
             account: account,
             event: 'reservation.confirmed',
             offset_minutes: 0)
      described_class.schedule_for(reservation)
    end

    it 'cancels checkin-based scheduled deliveries' do
      expect { described_class.reschedule_for_checkin_change(reservation) }
        .to(change do
          Captain::Lifecycle::Delivery.where(lifecycle_rule_id: checkin_rule.id, status: 'cancelled').count
        end)
    end
  end
end
