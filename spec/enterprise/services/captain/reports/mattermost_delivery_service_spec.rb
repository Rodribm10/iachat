require 'rails_helper'

RSpec.describe Captain::Reports::MattermostDeliveryService do
  subject(:service) { described_class.new(digest: digest, webhook_url: webhook_url) }

  let(:webhook_url) { 'https://mm.example.com/hooks/abc123' }
  let(:digest) do
    {
      account_id: 1,
      account_name: 'Grupo Nova',
      period_start: Date.new(2026, 4, 9),
      period_end: Date.new(2026, 4, 15),
      totals: {
        conversations: 250, messages: 980,
        conversations_delta_pct: 12.5,
        insights_analyzed: 2, units_analyzed: 2
      },
      unit_ranking: [
        { unit_id: 1, unit_name: 'Prime', conversations: 200, messages: 800, conversations_delta_pct: 10.0 }
      ],
      ai_performance: [
        { unit_id: 1, unit_name: 'Prime', conversations: 200, failures_count: 3, success_rate_pct: 98.5,
          top_failures: [{ 'description' => 'Erro X', 'frequency' => 2 }] }
      ],
      satisfaction: {
        most_dissatisfied: [{ unit_name: 'Prime', complaints_count: 2, negative_pct: 10.0, top_complaints: ['WiFi lento'], praises_count: 0,
                              top_praises: [] }],
        most_satisfied: [{ unit_name: 'Prime', praises_count: 5, positive_pct: 70.0, top_praises: ['Staff ótimo'], complaints_count: 0,
                           top_complaints: [] }]
      },
      top_topics: [{ 'topic' => 'Check-in', 'count' => 10 }],
      customer_opportunities: [{ 'opportunity' => 'Transfer do aeroporto', 'frequency' => 5 }],
      faq_gaps: [{ 'question' => 'Estacionamento?', 'frequency' => 3 }],
      complaints: [{ text: 'WiFi lento', frequency: 2 }],
      praises: [{ text: 'Staff ótimo', frequency: 4 }],
      most_requested_suites: [{ 'suite' => 'Presidencial', 'count' => 3 }],
      recommendations: ['Revisar WiFi'],
      period_summaries: []
    }
  end

  describe '#call' do
    context 'when webhook is missing' do
      it 'raises ArgumentError' do
        expect { described_class.new(digest: digest, webhook_url: '').call }.to raise_error(ArgumentError)
      end
    end

    context 'when webhook responds 200' do
      before do
        stub_request(:post, webhook_url).to_return(status: 200, body: 'ok')
      end

      it 'returns success true' do
        expect(service.call).to include(success: true, status: 200)
      end

      it 'posts a payload with attachments to the webhook' do
        service.call
        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body['attachments'].is_a?(Array) && body['attachments'].any? { |a| a['title'].to_s.include?('Performance da IA') }
        end)
      end

      it 'includes the customer opportunities block' do
        service.call
        expect(WebMock).to(have_requested(:post, webhook_url).with do |req|
          body = JSON.parse(req.body)
          body['attachments'].any? { |a| a['title'].to_s.include?('Oportunidades') }
        end)
      end
    end

    context 'when webhook fails' do
      before do
        stub_request(:post, webhook_url).to_return(status: 500, body: 'nope')
      end

      it 'returns success false with status' do
        expect(service.call).to include(success: false, status: 500)
      end
    end

    context 'when HTTP raises' do
      before do
        stub_request(:post, webhook_url).to_raise(StandardError.new('boom'))
      end

      it 'rescues and returns success false with error' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to include('boom')
      end
    end
  end
end
