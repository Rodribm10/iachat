require 'rails_helper'

RSpec.describe Captain::ContactMemories::SilenceDetectorJob do
  let(:account) { create(:account, custom_attributes: { 'captain_contact_memory_extraction_enabled' => true }) }
  let(:contact) { create(:contact, account: account) }

  # Widget inboxes auto-generate template messages (pre-chat form, etc.) with current
  # timestamps when an incoming message is created. To deterministically test "silence",
  # we update all messages in the conversation to an old created_at via update_all
  # (bypassing callbacks) after creation.
  def age_all_messages(conversation, age)
    conversation.messages.update_all(created_at: age) # rubocop:disable Rails/SkipsModelValidations
  end

  it 'enqueues extraction for conversations silent > 30 minutes' do
    conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conv, account: account)
    age_all_messages(conv, 35.minutes.ago)

    expect { described_class.perform_now }
      .to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob).with(conv.id)
  end

  it 'ignores conversations with recent activity' do
    conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conv, account: account)
    age_all_messages(conv, 5.minutes.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob)
  end

  it 'ignores conversations already extracted' do
    conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conv, account: account)
    age_all_messages(conv, 35.minutes.ago)
    create(:captain_contact_memory, account: account, contact: contact, source_conversation_id: conv.id)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob)
  end

  it 'ignores accounts with flag off' do
    account.update!(custom_attributes: { 'captain_contact_memory_extraction_enabled' => false })
    conv = create(:conversation, account: account, contact: contact)
    create(:message, conversation: conv, account: account)
    age_all_messages(conv, 35.minutes.ago)

    expect { described_class.perform_now }
      .not_to have_enqueued_job(Captain::ContactMemories::ExtractFromConversationJob)
  end
end
