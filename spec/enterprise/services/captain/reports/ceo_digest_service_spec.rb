require 'rails_helper'

RSpec.describe Captain::Reports::CeoDigestService do
  subject(:service) { described_class.new(account: account, period_start: period_start, period_end: period_end) }

  let(:account) { create(:account) }
  let(:inbox_prime) { create(:inbox, account: account, name: 'PRIME VL') }
  let(:inbox_dolce) { create(:inbox, account: account, name: 'DOLCE AMORE') }
  let(:period_end) { Date.current - 1.day }
  let(:period_start) { period_end - 6.days }

  describe '#call' do
    context 'with no insights' do
      it 'returns an empty digest flagged as empty' do
        result = service.call
        expect(result[:empty]).to be true
        expect(result[:totals][:conversations]).to eq(0)
        expect(result[:unit_ranking]).to be_empty
      end
    end

    context 'with insights per inbox (canal = unidade)' do
      before do
        create(:captain_conversation_insight,
               account: account, inbox: inbox_prime,
               period_start: period_start, period_end: period_end,
               conversations_count: 200, messages_count: 800)
        create(:captain_conversation_insight,
               account: account, inbox: inbox_dolce,
               period_start: period_start, period_end: period_end,
               conversations_count: 50, messages_count: 180)
      end

      it 'uses inbox name as unit_name in ranking' do
        ranking = service.call[:unit_ranking]
        expect(ranking.map { |u| u[:unit_name] }).to eq(['PRIME VL', 'DOLCE AMORE'])
      end

      it 'counts inboxes as units_analyzed' do
        totals = service.call[:totals]
        expect(totals[:units_analyzed]).to eq(2)
        expect(totals[:insights_analyzed]).to eq(2)
      end

      it 'totals conversations from inbox insights when no global exists' do
        totals = service.call[:totals]
        expect(totals[:conversations]).to eq(250)
        expect(totals[:messages]).to eq(980)
      end

      it 'computes AI performance per inbox' do
        perf = service.call[:ai_performance]
        expect(perf.map { |p| p[:unit_name] }).to contain_exactly('PRIME VL', 'DOLCE AMORE')
      end
    end

    context 'with a global insight and per-inbox insights' do
      before do
        create(:captain_conversation_insight,
               account: account, inbox: nil, captain_unit: nil,
               period_start: period_start, period_end: period_end,
               conversations_count: 500, messages_count: 2000)
        create(:captain_conversation_insight,
               account: account, inbox: inbox_prime,
               period_start: period_start, period_end: period_end,
               conversations_count: 200, messages_count: 800)
      end

      it 'uses the global insight for totals (no double counting)' do
        totals = service.call[:totals]
        expect(totals[:conversations]).to eq(500)
        expect(totals[:messages]).to eq(2000)
      end

      it 'still ranks inboxes separately' do
        ranking = service.call[:unit_ranking]
        expect(ranking.size).to eq(1)
        expect(ranking.first[:unit_name]).to eq('PRIME VL')
      end
    end

    context 'with WoW delta per inbox' do
      before do
        create(:captain_conversation_insight,
               account: account, inbox: inbox_prime,
               period_start: period_start, period_end: period_end,
               conversations_count: 120)
        create(:captain_conversation_insight,
               account: account, inbox: inbox_prime,
               period_start: period_start - 7.days, period_end: period_end - 7.days,
               conversations_count: 100)
      end

      it 'computes inbox-level WoW percentage delta' do
        ranking = service.call[:unit_ranking]
        expect(ranking.first[:conversations_delta_pct]).to eq(20.0)
      end
    end

    context 'when no inbox insights exist (fallback to captain_unit)' do
      let(:unit) { create(:captain_unit, account: account, name: 'Marca Prime') }

      before do
        create(:captain_conversation_insight,
               account: account, captain_unit: unit,
               period_start: period_start, period_end: period_end,
               conversations_count: 80)
      end

      it 'uses captain_unit name when no inbox insights exist' do
        ranking = service.call[:unit_ranking]
        expect(ranking.first[:unit_name]).to eq('Marca Prime')
      end
    end

    context 'when another account has insights' do
      let(:other_account) { create(:account) }

      before do
        create(:captain_conversation_insight,
               account: other_account, period_start: period_start, period_end: period_end,
               conversations_count: 999)
      end

      it 'does not leak data from other accounts' do
        expect(service.call[:totals][:conversations]).to eq(0)
      end
    end
  end
end
