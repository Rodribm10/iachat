require 'rails_helper'

RSpec.describe Captain::Reports::CeoDigestJob do
  let(:account) { create(:account) }
  let(:webhook_url) { 'https://mm.example.com/hooks/xyz' }
  let(:period_end) { Date.current - 1.day }
  let(:period_start) { period_end - 6.days }

  describe '#perform' do
    context 'when account has no config and no ENV fallback' do
      before { ENV.delete('CEO_DIGEST_MATTERMOST_WEBHOOK_URL') }

      it 'skips silently and does not call delivery' do
        expect(Captain::Reports::MattermostDeliveryService).not_to receive(:new)
        described_class.new.perform(account.id, period_start, period_end)
      end
    end

    context 'when account has ceo_digest disabled' do
      before do
        account.update!(custom_attributes: { 'ceo_digest' => { 'enabled' => false, 'mattermost_webhook_url' => webhook_url } })
      end

      it 'skips delivery' do
        expect(Captain::Reports::MattermostDeliveryService).not_to receive(:new)
        described_class.new.perform(account.id, period_start, period_end)
      end
    end

    context 'when account has webhook configured' do
      let(:delivery) { instance_double(Captain::Reports::MattermostDeliveryService, call: { success: true, status: 200 }) }

      before do
        account.update!(custom_attributes: { 'ceo_digest' => { 'enabled' => true, 'mattermost_webhook_url' => webhook_url,
                                                               'mattermost_channel' => '#ceo' } })
        allow(Captain::Reports::MattermostDeliveryService).to receive(:new).and_return(delivery)
      end

      it 'builds digest and calls delivery service with webhook and channel' do
        described_class.new.perform(account.id, period_start, period_end)
        expect(Captain::Reports::MattermostDeliveryService).to have_received(:new).with(
          hash_including(webhook_url: webhook_url, channel: '#ceo')
        )
      end
    end

    context 'when using ENV fallback' do
      let(:env_webhook) { 'https://mm.example.com/env-hook' }
      let(:delivery) { instance_double(Captain::Reports::MattermostDeliveryService, call: { success: true, status: 200 }) }

      around do |example|
        original = ENV.fetch('CEO_DIGEST_MATTERMOST_WEBHOOK_URL', nil)
        ENV['CEO_DIGEST_MATTERMOST_WEBHOOK_URL'] = env_webhook
        example.run
        ENV['CEO_DIGEST_MATTERMOST_WEBHOOK_URL'] = original
      end

      before do
        allow(Captain::Reports::MattermostDeliveryService).to receive(:new).and_return(delivery)
      end

      it 'uses ENV webhook when account has no config' do
        described_class.new.perform(account.id, period_start, period_end)
        expect(Captain::Reports::MattermostDeliveryService).to have_received(:new).with(
          hash_including(webhook_url: env_webhook)
        )
      end
    end

    context 'when delivery raises unexpectedly' do
      before do
        account.update!(custom_attributes: { 'ceo_digest' => { 'enabled' => true, 'mattermost_webhook_url' => webhook_url } })
        allow(Captain::Reports::MattermostDeliveryService).to receive(:new).and_raise(StandardError, 'boom')
      end

      it 'rescues and logs without raising' do
        expect { described_class.new.perform(account.id, period_start, period_end) }.not_to raise_error
      end
    end
  end
end
