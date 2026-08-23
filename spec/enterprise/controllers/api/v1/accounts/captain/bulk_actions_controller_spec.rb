require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::BulkActions', type: :request do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_with_custom_role) { create(:user, account: account, role: :agent) }
  let!(:pending_responses) do
    create_list(
      :captain_assistant_response,
      2,
      assistant: assistant,
      account: account,
      status: 'pending'
    )
  end
  let!(:documents) do
    create_list(
      :captain_document,
      2,
      assistant: assistant,
      account: account
    )
  end

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'POST /api/v1/accounts/:account_id/captain/bulk_actions' do
    context 'when approving responses' do
      let(:valid_params) do
        {
          type: 'AssistantResponse',
          ids: pending_responses.map(&:id),
          fields: { status: 'approve' }
        }
      end

      it 'does not approve the responses if the user is an agent without knowledge base permission' do
        post "/api/v1/accounts/#{account.id}/captain/bulk_actions",
             params: valid_params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)

        pending_responses.each do |response|
          expect(response.reload.status).to eq('pending')
        end
      end
    end

    context 'when deleting responses' do
      let(:delete_params) do
        {
          type: 'AssistantResponse',
          ids: pending_responses.map(&:id),
          fields: { status: 'delete' }
        }
      end

      it 'does not delete the responses if the user is an agent without knowledge base permission' do
        expect do
          post "/api/v1/accounts/#{account.id}/captain/bulk_actions",
               params: delete_params,
               headers: agent.create_new_auth_token,
               as: :json
        end.not_to change(Captain::AssistantResponse, :count)

        expect(response).to have_http_status(:forbidden)

        pending_responses.each do |response|
          expect(response.reload.status).to eq('pending')
        end
      end
    end

    context 'when the user has a custom role' do
      let(:approve_params) do
        {
          type: 'AssistantResponse',
          ids: pending_responses.map(&:id),
          fields: { status: 'approve' }
        }
      end

      it 'allows bulk actions with knowledge base permission' do
        custom_role = create(:custom_role, account: account, permissions: ['knowledge_base_manage'])
        AccountUser.find_by!(account: account, user: agent_with_custom_role).update!(custom_role: custom_role)

        post "/api/v1/accounts/#{account.id}/captain/bulk_actions",
             params: approve_params,
             headers: agent_with_custom_role.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:ok)
      end

      it 'rejects bulk actions without knowledge base permission' do
        custom_role = create(:custom_role, account: account, permissions: ['conversation_manage'])
        AccountUser.find_by!(account: account, user: agent_with_custom_role).update!(custom_role: custom_role)

        post "/api/v1/accounts/#{account.id}/captain/bulk_actions",
             params: approve_params,
             headers: agent_with_custom_role.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with invalid type' do
      let(:invalid_params) do
        {
          type: 'InvalidType',
          ids: pending_responses.map(&:id),
          fields: { status: 'approve' }
        }
      end

      it 'returns unprocessable entity status' do
        post "/api/v1/accounts/#{account.id}/captain/bulk_actions",
             params: invalid_params,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response[:success]).to be(false)

        # Verify no changes were made
        pending_responses.each do |response|
          expect(response.reload.status).to eq('pending')
        end
      end
    end

    context 'when deleting documents' do
      let(:document_delete_params) do
        {
          type: 'AssistantDocument',
          ids: documents.map(&:id),
          fields: { status: 'delete' }
        }
      end

      it 'deletes the documents and returns an empty array' do
        expect do
          post "/api/v1/accounts/#{account.id}/captain/bulk_actions",
               params: document_delete_params,
               headers: admin.create_new_auth_token,
               as: :json
        end.to change(Captain::Document, :count).by(-2)

        expect(response).to have_http_status(:ok)
        expect(json_response).to eq([])
      end
    end

    context 'with missing parameters' do
      let(:missing_params) do
        {
          type: 'AssistantResponse',
          fields: { status: 'approve' }
        }
      end

      it 'returns unprocessable entity status' do
        post "/api/v1/accounts/#{account.id}/captain/bulk_actions",
             params: missing_params,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response[:success]).to be(false)

        # Verify no changes were made
        pending_responses.each do |response|
          expect(response.reload.status).to eq('pending')
        end
      end
    end

    context 'with unauthorized user' do
      let(:unauthorized_user) { create(:user, account: create(:account)) }

      it 'returns unauthorized status' do
        post "/api/v1/accounts/#{account.id}/captain/bulk_actions",
             params: { type: 'AssistantResponse', ids: [1], fields: { status: 'approve' } },
             headers: unauthorized_user.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)

        # Verify no changes were made
        pending_responses.each do |response|
          expect(response.reload.status).to eq('pending')
        end
      end
    end
  end
end
