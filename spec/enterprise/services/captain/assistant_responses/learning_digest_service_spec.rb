require 'rails_helper'

RSpec.describe Captain::AssistantResponses::LearningDigestService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Bianca') }
  let(:period_start) { 7.days.ago.to_date }
  let(:period_end) { Date.current }
  let(:digest) { described_class.new(account: account, period_start: period_start, period_end: period_end).call }

  def learned(status:, **attrs)
    create(:captain_assistant_response, assistant: assistant, account: account,
                                        source: 'human_validated', status: status, **attrs)
  end

  describe '#call' do
    before do
      learned(status: 'trial', created_at: 2.days.ago)
      learned(status: 'trial', created_at: 3.days.ago)
      learned(status: 'pending', created_at: 1.day.ago)
      learned(status: 'approved', created_at: 40.days.ago, promoted_at: 2.days.ago)
      learned(status: 'retired', created_at: 40.days.ago, retired_at: 1.day.ago)
      # Fora da janela: não deve contar como aprendida nem promovida no período.
      learned(status: 'approved', created_at: 40.days.ago, promoted_at: 40.days.ago)
      # Veio de documento, não do loop de aprendizado: nunca entra no digest.
      create(:captain_assistant_response, assistant: assistant, account: account,
                                          source: 'document', status: 'pending', created_at: 1.day.ago)
    end

    it 'counts what was learned inside the period' do
      expect(digest[:totals][:aprendidas]).to eq(3)
    end

    it 'counts what is currently in quarantine' do
      expect(digest[:totals][:em_quarentena]).to eq(2)
    end

    it 'counts what was promoted inside the period' do
      expect(digest[:totals][:promovidas]).to eq(1)
    end

    it 'counts what was retired inside the period' do
      expect(digest[:totals][:aposentadas]).to eq(1)
    end

    it 'counts what is waiting for a human decision' do
      expect(digest[:totals][:aguardando_humano]).to eq(1)
    end

    it 'breaks the numbers down per assistant' do
      row = digest[:by_assistant].first

      expect(row[:assistant_name]).to eq('Bianca')
      expect(row[:aprendidas]).to eq(3)
    end

    it 'ignores FAQs that came from documents, counting only what the loop learned' do
      pending_from_documents = assistant.responses.pending.where(source: 'document').count

      expect(pending_from_documents).to eq(1)
      expect(digest[:totals][:aguardando_humano]).to eq(1)
    end
  end

  context 'when nothing happened' do
    it 'returns no rows so no message is sent' do
      expect(digest[:by_assistant]).to be_empty
    end
  end
end
