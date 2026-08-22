require 'rails_helper'

RSpec.describe DeleteObjectJob, type: :job do
  describe '#perform' do
    context 'when object is heavy (Inbox)' do
      let!(:account) { create(:account) }
      let!(:inbox) { create(:inbox, account: account) }

      before do
        create_list(:conversation, 3, account: account, inbox: inbox)
        ReportingEvent.create!(account: account, inbox: inbox, name: 'inbox_metric', value: 1.0)
      end

      it 'enqueues on the low queue' do
        expect { described_class.perform_later(inbox) }
          .to have_enqueued_job(described_class).with(inbox).on_queue('low')
      end

      it 'pre-deletes heavy associations and then destroys the object' do
        conv_ids = inbox.conversations.pluck(:id)
        ci_ids = inbox.contact_inboxes.pluck(:id)
        contact_ids = inbox.contacts.pluck(:id)
        re_ids = inbox.reporting_events.pluck(:id)

        described_class.perform_now(inbox)

        # Reload associations to ensure database state is current
        expect(Conversation.where(id: conv_ids).reload).to be_empty
        expect(ContactInbox.where(id: ci_ids).reload).to be_empty
        expect(ReportingEvent.where(id: re_ids).reload).to be_empty
        # Contacts should not be deleted for inbox destroy
        expect(Contact.where(id: contact_ids).reload).not_to be_empty
        expect { inbox.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'removes fazer.ai Captain and Jasmine inbox dependencies before destroying the inbox', :aggregate_failures do
        contact = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
        unit = create(:captain_unit, account: account)
        assistant = create(:captain_assistant, account: account)
        reservation_id = insert_row(
          :captain_reservations,
          account_id: account.id,
          inbox_id: inbox.id,
          contact_id: contact.id,
          contact_inbox_id: contact_inbox.id,
          suite_identifier: 'Suite 101',
          check_in_at: 1.day.from_now,
          check_out_at: 2.days.from_now,
          status: 0
        )

        unit.update!(inbox_id: inbox.id, concierge_inbox_id: inbox.id)
        create(:captain_inbox, captain_assistant: assistant, inbox: inbox, captain_unit: unit)
        create(:captain_conversation_insight, account: account, inbox: inbox)
        create(:captain_gallery_item, :inbox_scoped, account: account, inbox: inbox, captain_unit: unit)

        expect { described_class.perform_now(inbox) }.not_to raise_error

        expect(Inbox.exists?(inbox.id)).to be false
        expect(CaptainInbox.where(inbox_id: inbox.id)).to be_empty
        expect(Captain::Reservation.where(id: reservation_id)).to be_empty
        expect(Captain::GalleryItem.where(inbox_id: inbox.id)).to be_empty
        expect(Captain::ConversationInsight.where(inbox_id: inbox.id)).to be_empty
        expect(unit.reload.inbox_id).to be_nil
        expect(unit.concierge_inbox_id).to be_nil
      end
    end

    context 'when object is heavy (Account)' do
      let!(:account) { create(:account) }
      let!(:inbox1) { create(:inbox, account: account) }
      let!(:inbox2) { create(:inbox, account: account) }

      before do
        create_list(:conversation, 2, account: account, inbox: inbox1)
        create_list(:conversation, 1, account: account, inbox: inbox2)
        ReportingEvent.create!(account: account, name: 'acct_metric', value: 2.5)
        ReportingEvent.create!(account: account, inbox: inbox1, name: 'acct_inbox_metric', value: 3.5)
      end

      it 'pre-deletes conversations, contacts, inboxes and reporting events and then destroys the account' do
        conv_ids = account.conversations.pluck(:id)
        contact_ids = account.contacts.pluck(:id)
        inbox_ids = account.inboxes.pluck(:id)
        re_ids = account.reporting_events.pluck(:id)

        described_class.perform_now(account)

        # Reload associations to ensure database state is current
        expect(Conversation.where(id: conv_ids).reload).to be_empty
        expect(Contact.where(id: contact_ids).reload).to be_empty
        expect(Inbox.where(id: inbox_ids).reload).to be_empty
        expect(ReportingEvent.where(id: re_ids).reload).to be_empty
        expect { account.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when object is regular (Label)' do
      it 'just destroys the object' do
        label = create(:label)

        described_class.perform_now(label)

        expect { label.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  def insert_row(table, attributes)
    attributes = attributes.merge(created_at: Time.current, updated_at: Time.current)
    columns = attributes.keys
    values = attributes.values.map { |value| quoted_value(value) }
    sql = "INSERT INTO #{connection.quote_table_name(table)} (#{columns.map { |column| connection.quote_column_name(column) }.join(', ')}) " \
          "VALUES (#{values.join(', ')}) RETURNING id"

    connection.select_value(sql).to_i
  end

  def select_value(table, id, column)
    connection.select_value(
      "SELECT #{connection.quote_column_name(column)} FROM #{connection.quote_table_name(table)} WHERE id = #{Integer(id)}"
    )
  end

  def quoted_value(value)
    value = value.to_json if value.is_a?(Hash) || value.is_a?(Array)
    connection.quote(value)
  end

  def connection
    ActiveRecord::Base.connection
  end
end
