FactoryBot.define do
  factory :captain_contact_memory, class: 'Captain::ContactMemory' do
    account
    contact
    memory_type { 'preferencia' }
    content { 'Prefere Stilo com hidromassagem' }
    evidence { "cliente disse 'quero a Stilo com hidro de novo'" }
    confidence { 0.9 }
    scope { 'global' }
    last_verified_at { Time.current }
  end
end
