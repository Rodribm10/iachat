require 'rails_helper'

RSpec.describe Captain::Reserva::ProvisionUnitInSupabaseService do
  let(:account) { create(:account) }
  let(:brand) { Captain::Brand.create!(account: account, name: 'Hotel 1001 Noites Prime') }
  let(:unit) do
    Captain::Unit.create!(
      account: account,
      brand: brand,
      name: 'PrimeAL',
      visible_suite_categories: %w[Alexa Stilo Hidromassagem]
    )
  end

  let(:supabase_url) { 'https://supabase.test' }
  let(:supabase_key) { 'anon-key-test' }
  let(:marca_uuid) { 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' }
  let(:unidade_uuid) { 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('RESERVA_1001_SUPABASE_URL', nil).and_return(supabase_url)
    allow(ENV).to receive(:fetch).with('RESERVA_1001_SUPABASE_ANON_KEY', nil).and_return(supabase_key)
    allow(ENV).to receive(:fetch).with('RESERVA_1001_SUPABASE_SCHEMA', described_class::DEFAULT_SCHEMA).and_return('reserva_hotel')
  end

  context 'when tudo está configurado' do
    before do
      stub_request(:get, "#{supabase_url}/rest/v1/marcas")
        .with(query: hash_including('nome' => "eq.#{brand.name}", 'tenant_id' => 'eq.1'))
        .to_return(status: 200, body: [{ id: marca_uuid }].to_json, headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, "#{supabase_url}/rest/v1/unidades")
        .with(query: { 'on_conflict' => 'tenant_id,chatwoot_unit_id' })
        .to_return(
          status: 201,
          body: [{ id: unidade_uuid, tenant_id: 1, id_marca: marca_uuid }].to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'retorna sucesso e grava IDs do Supabase no Captain::Unit' do
      result = described_class.new(unit: unit).perform

      expect(result[:success]).to be true
      expect(result[:supabase_unit_id]).to eq(unidade_uuid)

      unit.reload
      expect(unit.supabase_unit_id).to eq(unidade_uuid)
      expect(unit.supabase_tenant_id).to eq(1)
      expect(unit.supabase_marca_id).to eq(marca_uuid)
    end

    it 'envia categorias_visiveis e chatwoot_unit_id no payload' do
      described_class.new(unit: unit).perform

      expect(WebMock).to have_requested(:post, "#{supabase_url}/rest/v1/unidades").with(
        query: { 'on_conflict' => 'tenant_id,chatwoot_unit_id' },
        body: hash_including(
          'nome' => unit.name,
          'id_marca' => marca_uuid,
          'tenant_id' => 1,
          'chatwoot_unit_id' => unit.id,
          'categorias_visiveis' => %w[Alexa Stilo Hidromassagem],
          'ativa' => true
        )
      )
    end
  end

  context 'when há erros' do
    it 'retorna erro quando ENV não está configurado' do
      allow(ENV).to receive(:fetch).with('RESERVA_1001_SUPABASE_URL', nil).and_return(nil)
      result = described_class.new(unit: unit).perform
      expect(result[:success]).to be false
      expect(result[:error]).to match(/Supabase não configurado/)
    end

    it 'retorna erro quando marca não existe no Supabase' do
      stub_request(:get, "#{supabase_url}/rest/v1/marcas")
        .with(query: hash_including('nome' => "eq.#{brand.name}"))
        .to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })

      result = described_class.new(unit: unit).perform
      expect(result[:success]).to be false
      expect(result[:error]).to match(/marca .* não encontrada/)
    end

    it 'retorna erro e não grava IDs quando upsert falha' do
      stub_request(:get, "#{supabase_url}/rest/v1/marcas")
        .to_return(status: 200, body: [{ id: marca_uuid }].to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, "#{supabase_url}/rest/v1/unidades")
        .to_return(status: 500, body: '{"message":"err"}')

      result = described_class.new(unit: unit).perform
      expect(result[:success]).to be false
      expect(unit.reload.supabase_unit_id).to be_nil
    end
  end
end
