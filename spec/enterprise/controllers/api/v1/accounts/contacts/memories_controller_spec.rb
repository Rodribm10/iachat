require 'rails_helper'

RSpec.describe Api::V1::Accounts::Contacts::MemoriesController, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let!(:memory) { create(:captain_contact_memory, account: account, contact: contact) }

  describe 'GET #index' do
    it 'returns memories for the contact' do
      get "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/memories",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data'].size).to eq(1)
    end
  end

  describe 'PATCH #update' do
    it 'updates content and re-embeds' do
      expect do
        patch "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/memories/#{memory.id}",
              params: { content: 'updated content' },
              headers: admin.create_new_auth_token
      end.to have_enqueued_job(Captain::ContactMemories::UpdateEmbeddingJob)

      expect(memory.reload.content).to eq('updated content')
    end
  end

  describe 'DELETE #destroy' do
    it 'soft-deletes' do
      delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/memories/#{memory.id}",
             headers: admin.create_new_auth_token

      expect(memory.reload.deleted_at).not_to be_nil
    end
  end

  describe 'DELETE collection (forget all)' do
    it 'soft-deletes all memories for the contact' do
      create_list(:captain_contact_memory, 3, account: account, contact: contact)

      delete "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/memories",
             headers: admin.create_new_auth_token

      expect(Captain::ContactMemory.for_contact(contact.id).where(deleted_at: nil).count).to eq(0)
    end
  end
end
