require 'rails_helper'

RSpec.describe V2::Reports::InboxLeadsSummaryBuilder do
  let(:account) { create(:account) }
  let(:inbox)   { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  let(:since_t) { 30.days.ago.beginning_of_day }
  let(:until_t) { Time.current.end_of_day }

  let(:base_params) do
    {
      inbox_id: inbox.id,
      since: since_t.to_i.to_s,
      until: until_t.to_i.to_s,
      group_by: 'day'
    }
  end

  def build(params = base_params)
    described_class.new(account, params).build
  end

  def total_for(rows, key)
    rows.sum { |r| r[key] }
  end

  describe '#build' do
    context 'when no inbox is provided or invalid' do
      it 'returns empty array when inbox_id missing' do
        expect(build(base_params.except(:inbox_id))).to eq([])
      end

      it 'returns empty array when range missing' do
        expect(build(base_params.except(:since))).to eq([])
      end

      it 'returns empty array when inbox does not belong to account' do
        foreign_inbox = create(:inbox, account: create(:account))
        expect(build(base_params.merge(inbox_id: foreign_inbox.id))).to eq([])
      end
    end

    context 'when classifying conversations' do
      it 'counts as new_lead when contact has no prior conversation' do
        contact = create(:contact, account: account)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 2.days.ago)

        rows = build
        expect(total_for(rows, :new_leads)).to eq(1)
        expect(total_for(rows, :returning)).to eq(0)
        expect(total_for(rows, :others)).to eq(0)
      end

      it 'counts as returning when prior conversation was resolved >24h ago' do
        contact = create(:contact, account: account)
        prior = create(:conversation, account: account, inbox: other_inbox, contact: contact, created_at: 10.days.ago)
        create(:reporting_event, account: account, inbox: other_inbox, conversation: prior,
                                 name: 'conversation_resolved', value: 100, value_in_business_hours: 50,
                                 created_at: 5.days.ago)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago)

        rows = build
        expect(total_for(rows, :new_leads)).to eq(0)
        expect(total_for(rows, :returning)).to eq(1)
        expect(total_for(rows, :others)).to eq(0)
      end

      it 'counts as others when prior conversation was resolved <24h ago' do
        contact = create(:contact, account: account)
        prior = create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 2.days.ago)
        create(:reporting_event, account: account, inbox: inbox, conversation: prior,
                                 name: 'conversation_resolved', value: 100, value_in_business_hours: 50,
                                 created_at: 3.hours.ago)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.hour.ago)

        rows = build
        expect(total_for(rows, :new_leads)).to eq(0)
        expect(total_for(rows, :returning)).to eq(0)
        expect(total_for(rows, :others)).to eq(1)
      end

      it 'counts as others when contact had prior conversation but it was never resolved' do
        contact = create(:contact, account: account)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 5.days.ago)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago)

        rows = build
        expect(total_for(rows, :new_leads)).to eq(1) # the older one
        expect(total_for(rows, :returning)).to eq(0)
        expect(total_for(rows, :others)).to eq(1) # the newer one
      end

      it 'considers prior conversations from any inbox of the account (network-wide)' do
        contact = create(:contact, account: account)
        prior = create(:conversation, account: account, inbox: other_inbox, contact: contact, created_at: 10.days.ago)
        create(:reporting_event, account: account, inbox: other_inbox, conversation: prior,
                                 name: 'conversation_resolved', value: 100, value_in_business_hours: 50,
                                 created_at: 5.days.ago)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago)

        rows = build
        expect(total_for(rows, :new_leads)).to eq(0)
        expect(total_for(rows, :returning)).to eq(1)
      end
    end

    context 'when scoped to a specific inbox' do
      it 'only counts conversations of the requested inbox' do
        contact_a = create(:contact, account: account)
        contact_b = create(:contact, account: account)
        create(:conversation, account: account, inbox: inbox, contact: contact_a, created_at: 1.day.ago)
        create(:conversation, account: account, inbox: other_inbox, contact: contact_b, created_at: 1.day.ago)

        rows = build
        expect(total_for(rows, :new_leads)).to eq(1)
      end
    end

    context 'when filtering by period range' do
      it 'ignores conversations outside the range' do
        contact = create(:contact, account: account)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 60.days.ago)

        rows = build
        expect(total_for(rows, :new_leads)).to eq(0)
      end
    end

    context 'when validating response shape' do
      it 'returns rows with iso8601 period and integer counts' do
        contact = create(:contact, account: account)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago)

        rows = build
        expect(rows).to all(include(:period, :new_leads, :returning, :others))
        expect(rows.first[:period]).to match(/\d{4}-\d{2}-\d{2}T/)
      end
    end
  end
end
