require 'rails_helper'

RSpec.describe LandingHosts::PromotionSyncSchedulerJob do
  it 'enqueues the job' do
    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue('scheduled_jobs')
  end

  it 'triggers sync on all landing hosts' do
    landing_host_one = build_stubbed(:landing_host, hostname: 'promo-1.example.com')
    landing_host_two = build_stubbed(:landing_host, hostname: 'promo-2.example.com')

    allow(landing_host_one).to receive(:sync_promotion_to_faq)
    allow(landing_host_two).to receive(:sync_promotion_to_faq)

    allow(LandingHost).to receive(:find_each).and_yield(landing_host_one).and_yield(landing_host_two)

    described_class.perform_now

    expect(landing_host_one).to have_received(:sync_promotion_to_faq)
    expect(landing_host_two).to have_received(:sync_promotion_to_faq)
  end
end
