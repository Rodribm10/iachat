FactoryBot.define do
  factory :lead_click do
    inbox_id { 1 }
    ip { 'MyString' }
    user_agent { 'MyString' }
    hostname { 'MyString' }
    source { 'MyString' }
    status { 1 }
  end
end
