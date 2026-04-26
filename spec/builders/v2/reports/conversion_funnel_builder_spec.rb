require 'rails_helper'

RSpec.describe V2::Reports::ConversionFunnelBuilder do
  let(:account) { create(:account) }
  let(:inbox)   { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }

  let(:since_t) { 30.days.ago.beginning_of_day }
  let(:until_t) { Time.current.end_of_day }

  let(:base_params) do
    {
      since: since_t.to_i.to_s,
      until: until_t.to_i.to_s
    }
  end

  def build(params = base_params)
    described_class.new(account, params).metrics
  end

  describe '#metrics' do
    context 'with empty period' do
      it 'returns zeroed metrics' do
        result = build
        expect(result[:leads]).to eq({ total: 0, new: 0, returning: 0 })
        expect(result[:reservations]).to eq({ created: 0, paid: 0 })
        expect(result[:conversion_rates][:lead_to_paid_reservation]).to eq(0)
      end
    end

    context 'with leads only (no reservations)' do
      it 'counts conversations as leads' do
        contact = create(:contact, account: account)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago)

        result = build
        expect(result[:leads][:total]).to eq(1)
        expect(result[:leads][:new]).to eq(1)
        expect(result[:reservations][:paid]).to eq(0)
      end
    end

    context 'when classifying new vs returning leads' do
      it 'separates contacts with prior history' do
        contact = create(:contact, account: account)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 5.days.ago)
        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago)

        result = build
        expect(result[:leads][:total]).to eq(2)
        expect(result[:leads][:new]).to eq(1)
        expect(result[:leads][:returning]).to eq(1)
      end
    end

    context 'when classifying reservation statuses' do
      let(:contact) { create(:contact, account: account) }
      let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }

      it 'ignores draft reservations from "created"' do
        create(:captain_reservation, account: account, inbox: inbox, contact: contact,
                                     contact_inbox: contact_inbox, status: :draft, created_at: 1.day.ago)
        result = build
        expect(result[:reservations][:created]).to eq(0)
      end

      it 'counts non-draft as created' do
        create(:captain_reservation, account: account, inbox: inbox, contact: contact,
                                     contact_inbox: contact_inbox, status: :pending_payment, created_at: 1.day.ago)
        result = build
        expect(result[:reservations][:created]).to eq(1)
        expect(result[:reservations][:paid]).to eq(0)
      end

      %i[active completed confirmed].each do |paid_status|
        it "counts #{paid_status} as paid" do
          create(:captain_reservation, account: account, inbox: inbox, contact: contact,
                                       contact_inbox: contact_inbox, status: paid_status, created_at: 1.day.ago)
          result = build
          expect(result[:reservations][:paid]).to eq(1)
        end
      end
    end

    context 'with inbox_id filter' do
      it 'restricts both conversations and reservations to that inbox' do
        contact = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
        contact_inbox_other = create(:contact_inbox, contact: contact, inbox: other_inbox)

        create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago)
        create(:conversation, account: account, inbox: other_inbox, contact: contact, created_at: 1.day.ago)
        create(:captain_reservation, account: account, inbox: inbox, contact: contact,
                                     contact_inbox: contact_inbox, status: :confirmed, created_at: 1.day.ago)
        create(:captain_reservation, account: account, inbox: other_inbox, contact: contact,
                                     contact_inbox: contact_inbox_other, status: :confirmed, created_at: 1.day.ago)

        result = build(base_params.merge(inbox_id: inbox.id))
        expect(result[:leads][:total]).to eq(1)
        expect(result[:reservations][:paid]).to eq(1)
      end
    end

    context 'when computing conversion rates' do
      it 'rounds to one decimal' do
        contact = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
        3.times { create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.day.ago) }
        create(:captain_reservation, account: account, inbox: inbox, contact: contact,
                                     contact_inbox: contact_inbox, status: :confirmed, created_at: 1.day.ago)

        result = build
        expect(result[:conversion_rates][:lead_to_paid_reservation]).to eq(33.3)
      end
    end
  end
end
