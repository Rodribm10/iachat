require 'rails_helper'

RSpec.describe LandingHost, type: :model do
  let(:account) { create(:account) }
  let(:portal) { create(:portal, account: account) }
  let(:inbox) { create(:inbox, account: account, portal: portal) }

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
                  valid_until: '2024-11-30'
                }
              ]
            })
    end

    it 'creates a new FAQ article when promotion is active' do
      expect do
        landing_host.save!
      end.to change(Article, :count).by(1)

      title = "Promoção Automática - #{landing_host.hostname.upcase}"
      article = portal.articles.find_by(title: title)
      expect(article).to be_present
      expect(article.title).to include("Promoção Automática - #{landing_host.hostname.upcase}")
      expect(article.content).to include('Black Friday 50% Off')
      expect(article.content).to include('BLACK50')
      expect(article.content).to include('Instagram')
      expect(article.status).to eq('published')
    end

    it 'archives an existing FAQ article when promotion is deactivated' do
      landing_host.save! # Automatically creates the article
      title = "Promoção Automática - #{landing_host.hostname.upcase}"
      article = portal.articles.find_by(title: title)
      expect(article.status).to eq('published')

      # Deactivate promotion
      landing_host.custom_config['promotions'].first['active'] = false
      landing_host.save!

      expect(article.reload.status).to eq('archived')
    end
  end
end
