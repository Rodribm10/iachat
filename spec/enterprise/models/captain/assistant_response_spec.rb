require 'rails_helper'

RSpec.describe Captain::AssistantResponse do
  let(:assistant) { create(:captain_assistant) }

  describe 'status lifecycle' do
    it 'exposes the four states of the learning cycle' do
      expect(described_class.statuses).to eq('pending' => 0, 'approved' => 1, 'trial' => 2, 'retired' => 3)
    end

    it 'keeps approved as the default so manual creation stays untouched' do
      response = create(:captain_assistant_response, assistant: assistant)

      expect(response).to be_approved
    end
  end

  describe '.retrievable' do
    let!(:approved) { create(:captain_assistant_response, assistant: assistant, status: 'approved') }
    let!(:trial) { create(:captain_assistant_response, assistant: assistant, status: 'trial') }

    before do
      create(:captain_assistant_response, assistant: assistant, status: 'pending')
      create(:captain_assistant_response, assistant: assistant, status: 'retired')
    end

    it 'returns live knowledge only: approved and trial' do
      expect(described_class.retrievable).to contain_exactly(approved, trial)
    end

    # Sem embedding a busca vetorial nunca encontra a resposta. Contá-la como
    # recuperável dava um número mentiroso — foi o que aconteceu quando o
    # provedor de embeddings caiu e uma FAQ ficou órfã, invisível mas "no ar".
    it 'exclui o que está sem embedding, porque a busca nunca encontraria' do
      orfa = create(:captain_assistant_response, assistant: assistant, status: 'approved', embedding: nil)

      expect(described_class.retrievable).not_to include(orfa)
      expect(described_class.sem_embedding).to include(orfa)
    end
  end

  describe '.trial_expired' do
    let!(:expired) { create(:captain_assistant_response, assistant: assistant, status: 'trial', trial_until: 1.day.ago) }

    before do
      create(:captain_assistant_response, assistant: assistant, status: 'trial', trial_until: 5.days.from_now)
      create(:captain_assistant_response, assistant: assistant, status: 'pending', trial_until: 1.day.ago)
    end

    it 'only returns quarantined responses whose deadline has passed' do
      expect(described_class.trial_expired).to contain_exactly(expired)
    end
  end

  describe '#promote!' do
    let(:response) do
      create(:captain_assistant_response, assistant: assistant, status: 'trial', trial_until: 1.day.ago)
    end

    it 'turns quarantined knowledge into permanent knowledge' do
      response.promote!

      expect(response).to be_approved
      expect(response.trial_until).to be_nil
      expect(response.promoted_at).to be_present
    end
  end

  describe '#retire!' do
    let(:response) { create(:captain_assistant_response, assistant: assistant, status: 'trial') }

    it 'removes the knowledge from retrieval without deleting the record' do
      response.retire!('corrigida novamente por humano')

      expect(response).to be_retired
      expect(response.retired_reason).to eq('corrigida novamente por humano')
      expect(response.retired_at).to be_present
      expect(described_class.retrievable).not_to include(response)
      expect(described_class.find_by(id: response.id)).to be_present
    end
  end

  describe 'source validation' do
    it 'accepts the known sources' do
      expect(build(:captain_assistant_response, assistant: assistant, source: 'human_validated')).to be_valid
    end

    it 'allows nil for legacy records' do
      expect(build(:captain_assistant_response, assistant: assistant, source: nil)).to be_valid
    end

    it 'rejects an unknown source' do
      expect(build(:captain_assistant_response, assistant: assistant, source: 'inventado')).not_to be_valid
    end
  end
end
