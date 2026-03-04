require 'rails_helper'

RSpec.describe LandingHost, type: :model do
  let(:account) { create(:account) }
  let(:portal) { create(:portal, account: account) }
  let(:inbox) { create(:inbox, account: account, portal: portal) }
  let(:assistant) { create(:captain_assistant, account: account) }

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('FRONTEND_URL', '').and_return('https://app.example.com')
    allow(ENV).to receive(:fetch).with('FRONTEND_URL', 'https://app.chatwoot.com').and_return('https://app.example.com')
  end

  describe 'LandingHostAiSyncable' do
    let(:landing_host) do
      build(:landing_host,
            inbox: inbox,
            hostname: 'promo.example.com',
            custom_config: {
              promotions: [
                {
                  active: true,
                  channel: 'Instagram',
                  title: 'Black Friday 50% Off',
                  description: 'Valid for all suites.',
                  coupon_code: 'BLACK50',
                  valid_until: '2099-11-30'
                },
                {
                  active: true,
                  channel: 'Facebook',
                  title: 'Pernoite 79,90',
                  description: 'Somente esta semana.',
                  coupon_code: 'FACE79',
                  valid_until: '2099-12-31'
                }
              ]
            })
    end

    it 'creates one article and one document per active promotion' do
      expect do
        landing_host.save!
      end.to change(Article, :count).by(2)
        .and change(Captain::Document, :count).by(2)

      synced_articles = portal.articles.where("meta -> 'landing_promotion_sync' ->> 'landing_host_id' = ?", landing_host.id.to_s)
      expect(synced_articles.count).to eq(2)
      expect(synced_articles.pluck(:title).join(' | ')).to include('Black Friday 50% Off')
      expect(synced_articles.pluck(:title).join(' | ')).to include('Pernoite 79,90')

      synced_documents = assistant.documents.where("metadata -> 'landing_promotion_sync' ->> 'landing_host_id' = ?", landing_host.id.to_s)
      expect(synced_documents.count).to eq(2)
      expect(synced_documents.map(&:content).join(' ')).to include('Black Friday 50% Off')
      expect(synced_documents.map(&:content).join(' ')).to include('Pernoite 79,90')
      expect(synced_documents).to all(be_available)
    end

    it 'removes article, document and FAQs for a promotion removed from config' do
      landing_host.save!

      synced_documents = assistant.documents.where("metadata -> 'landing_promotion_sync' ->> 'landing_host_id' = ?", landing_host.id.to_s)
      synced_documents.each do |document|
        create(:captain_assistant_response, assistant: assistant, account: account, documentable: document)
      end

      # keep only one promotion active
      landing_host.custom_config['promotions'] = [landing_host.custom_config['promotions'].first]

      expect do
        landing_host.save!
      end.to change(Article, :count).by(-1)
        .and change(Captain::Document, :count).by(-1)
        .and change(Captain::AssistantResponse, :count).by(-1)
    end

    it 'treats expired promotions as inactive and cleans synced knowledge' do
      landing_host.save!
      landing_host.custom_config['promotions'].first['valid_until'] = 1.day.ago.strftime('%d/%m/%Y')
      landing_host.custom_config['promotions'].second['valid_until'] = 1.day.ago.strftime('%d/%m/%Y')

      expect do
        landing_host.save!
      end.to change(Article, :count).by(-2)
        .and change(Captain::Document, :count).by(-2)
    end
  end
end
