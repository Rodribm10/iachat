require 'rails_helper'

RSpec.describe Captain::Hermes::KnownFactReplyService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def vincular_assistente(profile:, unit: nil)
    assistant = create(
      :captain_assistant,
      account: account,
      engine: 'hermes',
      hermes_profile_name: profile,
      hermes_webhook_base_url: 'http://hermes.test',
      captain_unit: unit
    )
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox, captain_unit: unit)
    inbox.reload
    assistant
  end

  def criar_preco(unit:, key:, aliases:, period:, amount:, day_bucket: nil)
    category = Captain::PricingCategory.create!(
      captain_unit: unit,
      key: key,
      aliases: aliases,
      extra_person_starts_at: 3
    )
    Captain::PricingAmount.create!(pricing_category: category, period: period, amount: amount, day_bucket: day_bucket)
  end

  describe 'localizacao' do
    it 'mantem catalogo para toda a frota hoteleira do Hermes' do
      expected_profiles = %w[
        bianca_h camila_samambaia isabela_instagram juliana_qnn1 lara_h lia_anuncios nina
        padova_setor_o prime_ade primeinstagram recanto_emas site_atendente valentina
      ]

      expect(Captain::Hermes::KnownFactsCatalog.profiles.keys).to include(*expected_profiles)
      expected_profiles.each do |profile|
        locations = Captain::Hermes::KnownFactsCatalog.profile(profile).fetch('locations')
        expect(locations).not_to be_empty
        expect(locations).to all(include('name', 'url'))
        expect(locations.pluck('url')).to all(start_with('https://'))
      end
    end

    it 'devolve o link oficial da Juliana sem depender do LLM' do
      vincular_assistente(profile: 'juliana_qnn1')

      result = described_class.new(
        conversation: conversation,
        content: 'Pode me mandar a localização por favor?'
      ).call

      expect(result.kind).to eq(:location)
      expect(result).to be_exclusive
      expect(result.content).to include('https://maps.app.goo.gl/bogrUpmGoiDhUgeR8')
      expect(result.content).not_to include('busca no Maps')
    end

    it 'lista todas as unidades quando uma atendente de marca recebe pedido generico' do
      vincular_assistente(profile: 'site_atendente')

      result = described_class.new(conversation: conversation, content: 'Me manda a localização').call

      expect(result.kind).to eq(:location)
      expect(result.content).to include('QNN01', 'Setor O', 'Samambaia', 'Recanto das Emas')
      expect(result.content.scan(%r{https://}).size).to eq(4)
    end

    it 'seleciona somente a unidade citada em atendimento multiunidade' do
      vincular_assistente(profile: 'isabela_instagram')

      result = described_class.new(conversation: conversation, content: 'Onde fica a unidade do Recanto?').call

      expect(result.content).to include('Recanto das Emas')
      expect(result.content).not_to include('Samambaia', 'Setor O', 'QNN01')
    end

    it 'nao sequestra uma pergunta que nao e fato conhecido' do
      vincular_assistente(profile: 'juliana_qnn1')

      result = described_class.new(conversation: conversation, content: 'Quero fazer uma reserva para sexta').call

      expect(result).to be_nil
    end
  end

  describe 'precos estruturados' do
    let(:brand) { create(:captain_brand, account: account) }
    let(:unit) { create(:captain_unit, account: account, brand: brand, name: 'QNN01') }

    before do
      vincular_assistente(profile: 'juliana_qnn1', unit: unit)
      criar_preco(unit: unit, key: 'standard', aliases: ['standard'], period: 'pernoite_promo', amount: 100)
      criar_preco(unit: unit, key: 'hidromassagem', aliases: %w[hidro hidromassagem], period: 'pernoite_promo', amount: 250)
    end

    it 'responde quanto custa pernoite com todas as categorias disponiveis' do
      result = described_class.new(conversation: conversation, content: 'Quanto é o pernoite?').call

      expect(result.kind).to eq(:pricing)
      expect(result).to be_exclusive
      expect(result.content).to include('Standard: *R$ 100*')
      expect(result.content).to include('Hidromassagem: *R$ 250*')
    end

    it 'filtra a categoria quando o cliente especifica hidro' do
      result = described_class.new(conversation: conversation, content: 'Pernoite da hidro quanto fica?').call

      expect(result.content).to include('Hidromassagem: *R$ 250*')
      expect(result.content).not_to include('Standard')
    end

    it 'nao confunde quanto tempo de carro com pergunta de preco' do
      result = described_class.new(conversation: conversation, content: 'Quanto tempo de carro até o centro?').call

      expect(result).to be_nil
    end

    it 'deixa o Hermes complementar quando o preco depende de pessoas ou cafe' do
      pessoas = described_class.new(
        conversation: conversation,
        content: 'Quanto fica o pernoite para 3 pessoas?'
      ).call
      cafe = described_class.new(conversation: conversation, content: 'Pernoite tem café?').call

      expect(pessoas).not_to be_exclusive
      expect(cafe).not_to be_exclusive
    end
  end
end
