require 'rails_helper'

RSpec.describe 'Api::V1::Tracking', type: :request do
  describe 'POST /track/click' do
    let(:valid_params) do
      {
        hostname: 'test.com',
        source: 'facebook',
        campanha: 'summer26',
        lp: '/promo'
      }
    end

    context 'when tracking a click' do
      it 'creates a lead click and returns no_content' do
        expect do
          post '/track/click', params: valid_params, as: :json
        end.to change(LeadClick, :count).by(1)

        expect(response).to have_http_status(:no_content)
        click = LeadClick.last
        expect(click.hostname).to eq('test.com')
        expect(click.source).to eq('facebook')
        expect(click.status).to eq('clicked')
      end

      it 'resolves the inbox if landing host exists' do
        host = create(:landing_host, hostname: 'test.com', active: true)

        post '/track/click', params: valid_params, as: :json

        expect(LeadClick.last.inbox_id).to eq(host.inbox_id)
      end
    end
  end
end
