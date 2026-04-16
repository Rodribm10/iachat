# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'captain_unit factory' do # rubocop:disable RSpec/DescribeClass
  it 'cria uma unit com conta e brand próprios' do
    unit = create(:captain_unit)
    expect(unit).to be_persisted
    expect(unit.account).to be_present
    expect(unit.brand).to be_present
    expect(unit.brand.account_id).to eq(unit.account_id)
  end

  it 'usa a conta fornecida' do
    account = create(:account)
    unit = create(:captain_unit, account: account)
    expect(unit.account).to eq(account)
    expect(unit.brand.account_id).to eq(account.id)
  end

  it 'reusa um brand existente da mesma conta' do
    account = create(:account)
    brand = create(:captain_brand, account: account)
    unit = create(:captain_unit, account: account)
    expect(unit.brand).to eq(brand)
  end
end
