FactoryBot.define do
  factory :captain_conversation_insight, class: 'Captain::ConversationInsight' do
    association :account
    period_start { Date.current - 7.days }
    period_end { Date.current - 1.day }
    status { 'done' }
    conversations_count { 10 }
    messages_count { 40 }
    generated_at { Time.current }

    payload do
      {
        'top_topics' => [{ 'topic' => 'Check-in', 'count' => 5, 'description' => 'Dúvidas sobre check-in' }],
        'ai_failures' => [{ 'description' => 'Não soube responder sobre estacionamento', 'example' => 'Tem estacionamento?', 'frequency' => 3 }],
        'faq_gaps' => [{ 'question' => 'Horário de check-out?', 'frequency' => 2 }],
        'sentiment' => { 'positive_count' => 6, 'negative_count' => 2, 'neutral_count' => 2, 'summary' => 'Maioria satisfeita.' },
        'highlights' => { 'praises' => ['Atendimento rápido'], 'complaints' => ['WiFi lento'] },
        'most_requested_suites' => [{ 'suite' => 'Suíte Presidencial', 'count' => 3 }],
        'price_reactions' => { 'summary' => 'Aceitação boa.', 'objections_count' => 1 },
        'customer_opportunities' => [{ 'opportunity' => 'Transfer do aeroporto', 'frequency' => 2, 'example' => 'Vocês fazem transfer?' }],
        'recommendations' => ['Criar FAQ sobre estacionamento'],
        'period_summary' => 'Semana com 10 conversas e sentimento predominante positivo.'
      }
    end

    trait :processing do
      status { 'processing' }
      payload { nil }
      generated_at { nil }
    end

    trait :with_unit do
      association :captain_unit, factory: :captain_unit
    end

    trait :with_inbox do
      association :inbox, factory: :inbox
    end

    trait :empty do
      conversations_count { 0 }
      messages_count { 0 }
      payload do
        {
          'top_topics' => [], 'ai_failures' => [], 'faq_gaps' => [],
          'sentiment' => { 'positive_count' => 0, 'negative_count' => 0, 'neutral_count' => 0, 'summary' => '' },
          'highlights' => { 'praises' => [], 'complaints' => [] },
          'most_requested_suites' => [], 'price_reactions' => { 'summary' => '', 'objections_count' => 0 },
          'customer_opportunities' => [], 'recommendations' => [], 'period_summary' => 'Sem dados.'
        }
      end
    end
  end
end
