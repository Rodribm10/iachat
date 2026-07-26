require 'rails_helper'

RSpec.describe Captain::AssistantResponses::ProbationJob do
  let(:assistant) { create(:captain_assistant) }

  describe '#perform' do
    let!(:expired) do
      create(:captain_assistant_response, assistant: assistant, status: 'trial', trial_until: 1.day.ago)
    end
    let!(:still_in_quarantine) do
      create(:captain_assistant_response, assistant: assistant, status: 'trial', trial_until: 10.days.from_now)
    end
    let!(:rejected) do
      create(:captain_assistant_response, assistant: assistant, status: 'pending')
    end

    it 'promotes knowledge that survived the quarantine' do
      described_class.perform_now

      expect(expired.reload).to be_approved
      expect(expired.trial_until).to be_nil
    end

    it 'leaves knowledge still inside the quarantine window alone' do
      described_class.perform_now

      expect(still_in_quarantine.reload).to be_trial
    end

    it 'never promotes what the judge rejected' do
      described_class.perform_now

      expect(rejected.reload).to be_pending
    end

    it 'returns how many were promoted' do
      expect(described_class.perform_now).to eq(1)
    end

    it 'logs and moves on when a promotion fails' do
      allow_any_instance_of(described_class.name.constantize).to receive(:perform).and_call_original # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Captain::AssistantResponse).to receive(:promote!).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance
      allow(Rails.logger).to receive(:error)

      expect { described_class.perform_now }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/failed to promote/)
    end
  end
end
