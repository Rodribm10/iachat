require 'rails_helper'

RSpec.describe 'Captain lifecycle routes', type: :routing do
  it 'routes GET /api/v1/accounts/1/captain/lifecycle_rules' do
    expect(get: '/api/v1/accounts/1/captain/lifecycle_rules')
      .to route_to(controller: 'api/v1/accounts/captain/lifecycle_rules', action: 'index',
                   account_id: '1', format: 'json')
  end

  it 'routes GET /api/v1/accounts/1/captain/lifecycle_config' do
    expect(get: '/api/v1/accounts/1/captain/lifecycle_config')
      .to route_to(controller: 'api/v1/accounts/captain/lifecycle_configs', action: 'show',
                   account_id: '1', format: 'json')
  end

  it 'routes GET /api/v1/accounts/1/captain/lifecycle_deliveries' do
    expect(get: '/api/v1/accounts/1/captain/lifecycle_deliveries')
      .to route_to(controller: 'api/v1/accounts/captain/lifecycle_deliveries', action: 'index',
                   account_id: '1', format: 'json')
  end

  it 'routes PATCH /api/v1/accounts/1/captain/units/5/concierge' do
    expect(patch: '/api/v1/accounts/1/captain/units/5/concierge')
      .to route_to(controller: 'api/v1/accounts/captain/units', action: 'update_concierge',
                   account_id: '1', id: '5', format: 'json')
  end
end
