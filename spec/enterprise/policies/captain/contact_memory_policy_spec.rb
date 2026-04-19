require 'rails_helper'

RSpec.describe Captain::ContactMemoryPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin_context) { { user: admin, account: account, account_user: admin.account_users.first } }
  let(:agent_context) { { user: agent, account: account, account_user: agent.account_users.first } }
  let(:record) { create(:captain_contact_memory, account: account) }

  permissions :index? do
    context 'when user is administrator' do
      it { expect(subject).to permit(admin_context, record) }
    end

    context 'when user is agent' do
      it { expect(subject).to permit(agent_context, record) }
    end
  end

  permissions :update?, :destroy?, :bulk_destroy? do
    context 'when user is administrator' do
      it { expect(subject).to permit(admin_context, record) }
    end

    context 'when user is agent' do
      it { expect(subject).not_to permit(agent_context, record) }
    end
  end
end
