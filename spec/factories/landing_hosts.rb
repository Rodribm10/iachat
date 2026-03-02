FactoryBot.define do
  factory :landing_host do
    hostname { 'MyString' }
    unit_code { 'MyString' }
    inbox_id { 1 }
    active { false }
  end
end
