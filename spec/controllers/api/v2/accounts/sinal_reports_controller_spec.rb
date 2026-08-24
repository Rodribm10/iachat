require 'rails_helper'

RSpec.describe 'Sinal Reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  describe 'GET /api/v2/accounts/:account_id/sinal_reports/media_summary' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/sinal_reports/media_summary"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin' do
      before do
        create(:message, :with_attachment, account: account, conversation: conversation, created_at: 2.days.ago)
        create(:message, :with_attachment, account: account, conversation: conversation, created_at: 40.days.ago)
      end

      it 'counts every attachment when no period is given (compat with the previous all-time behavior)' do
        get "/api/v2/accounts/#{account.id}/sinal_reports/media_summary",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['by_type']['image']).to eq(2)
      end

      it 'scopes the counts to the requested since/until window' do
        get "/api/v2/accounts/#{account.id}/sinal_reports/media_summary",
            params: { since: 5.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['by_type']['image']).to eq(1)
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/sinal_reports/media_timeseries' do
    before do
      create(:message, :with_attachment, account: account, conversation: conversation, created_at: 1.day.ago)
      create(:message, :with_attachment, account: account, conversation: conversation, created_at: 90.days.ago)
    end

    it 'restricts the buckets to the requested since/until window' do
      get "/api/v2/accounts/#{account.id}/sinal_reports/media_timeseries",
          params: { granularity: 'day', since: 5.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      total = response.parsed_body['buckets'].sum { |bucket| bucket['values']['image'].to_i }
      expect(total).to eq(1)
    end

    it 'falls back to the fixed rolling window when no period is given' do
      get "/api/v2/accounts/#{account.id}/sinal_reports/media_timeseries",
          params: { granularity: 'day' },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      total = response.parsed_body['buckets'].sum { |bucket| bucket['values']['image'].to_i }
      expect(total).to eq(1) # a mensagem de 90 dias atrás cai fora da janela padrão de 60 dias
    end
  end

  describe 'GET /api/v2/accounts/:account_id/sinal_reports/media_breakdown' do
    before do
      create(:message, :with_attachment, account: account, conversation: conversation, created_at: 1.day.ago)
      create(:message, :with_attachment, account: account, conversation: conversation, created_at: 90.days.ago)
    end

    it 'only counts attachments inside the requested period' do
      get "/api/v2/accounts/#{account.id}/sinal_reports/media_breakdown",
          params: { scope: 'individual', since: 5.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['rows'].sum { |row| row['total'] }).to eq(1)
    end
  end

  describe 'GET /api/v2/accounts/:account_id/sinal_reports/media_messages' do
    before do
      create(:message, :with_attachment, account: account, conversation: conversation, created_at: 1.day.ago)
      create(:message, :with_attachment, account: account, conversation: conversation, created_at: 90.days.ago)
    end

    it 'only returns messages inside the requested period' do
      get "/api/v2/accounts/#{account.id}/sinal_reports/media_messages",
          params: { since: 5.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['messages'].length).to eq(1)
    end
  end
end
