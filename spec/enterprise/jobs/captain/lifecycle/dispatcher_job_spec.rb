# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Lifecycle::DispatcherJob do
  let(:delivery) { create(:captain_lifecycle_delivery) }

  it 'calls Dispatcher#call' do
    dispatcher = instance_double(Captain::Lifecycle::Dispatcher)
    expect(Captain::Lifecycle::Dispatcher)
      .to receive(:new)
      .with(instance_of(Captain::Lifecycle::Delivery))
      .and_return(dispatcher)
    expect(dispatcher).to receive(:call)

    described_class.perform_now(delivery.id)
  end

  it 'silently skips missing delivery records' do
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
