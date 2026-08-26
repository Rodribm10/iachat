require 'rails_helper'

RSpec.describe Captain::Crm::SyncLeadsJob do
  let(:account) { create(:account) }
  let(:client) { instance_double(Captain::Crm::TwentyClient) }

  def conversation_with(labels, contact: nil)
    contact ||= create(:contact, account: account, name: 'Alina Galega', phone_number: '+5561999084787')
    conv = create(:conversation, account: account, contact: contact)
    conv.update_labels(labels)
    conv
  end

  def run
    with_modified_env(
      TWENTY_CRM_BASE_URL: 'https://crm.example.com',
      TWENTY_CRM_API_KEY: 'chave',
      TWENTY_CRM_ACCOUNT_IDS: account.id.to_s
    ) do
      described_class.perform_now
    end
  end

  before do
    allow(Captain::Crm::TwentyClient).to receive(:new).and_return(client)
  end

  it 'nao faz nada quando a integracao nao esta configurada' do
    expect(Captain::Crm::TwentyClient).not_to receive(:new)
    described_class.perform_now
  end

  it 'cria no CRM quem demonstrou interesse e guarda o id no contato' do
    conv = conversation_with(['quer_experimental'])
    expect(client).to receive(:create_person).with(
      hash_including(first_name: 'Alina', last_name: 'Galega', stage: 'QUER_EXPERIMENTAL')
    ).and_return('person-1')

    run

    attrs = conv.contact.reload.custom_attributes
    expect(attrs['twenty_person_id']).to eq('person-1')
    expect(attrs['twenty_stage']).to eq('QUER_EXPERIMENTAL')
  end

  # O pedido do dono: cliente novo entra, aluno atual nao. A regra ja e aplicada
  # pela Duda quando ela classifica LEAD vs ALUNO — aqui so garantimos que uma
  # conversa sem etiqueta de interesse nunca vira registro no CRM.
  it 'ignora quem nao demonstrou interesse (aluno atual, conversa comum)' do
    conversation_with(%w[cliente_aguardando reclamacao])
    expect(client).not_to receive(:create_person)

    run
  end

  it 'usa o estagio mais avancado quando ha mais de uma etiqueta' do
    conversation_with(%w[lead_novo visita_marcada quer_experimental])
    expect(client).to receive(:create_person).with(
      hash_including(stage: 'VISITA_MARCADA')
    ).and_return('person-2')

    run
  end

  it 'move o estagio de quem ja existe no CRM em vez de duplicar' do
    contact = create(:contact, account: account, name: 'Gustavo', phone_number: '+5561988887777',
                               custom_attributes: { 'twenty_person_id' => 'person-3', 'twenty_stage' => 'LEAD_NOVO' })
    conversation_with(['visita_marcada'], contact: contact)

    expect(client).not_to receive(:create_person)
    expect(client).to receive(:update_person).with(person_id: 'person-3', stage: 'VISITA_MARCADA')

    run
    expect(contact.reload.custom_attributes['twenty_stage']).to eq('VISITA_MARCADA')
  end

  # Idempotencia: o job roda a cada 5 minutos sobre uma janela de 7 dias. Sem
  # esta guarda, cada execucao reenviaria toda a base de leads da semana.
  it 'nao gasta chamada quando o estagio nao mudou' do
    contact = create(:contact, account: account, name: 'Paola',
                               custom_attributes: { 'twenty_person_id' => 'person-4', 'twenty_stage' => 'VISITA_MARCADA' })
    conversation_with(['visita_marcada'], contact: contact)

    expect(client).not_to receive(:create_person)
    expect(client).not_to receive(:update_person)

    run
  end

  it 'falha de um contato nao derruba a fila' do
    conversation_with(['lead_novo'])
    allow(client).to receive(:create_person).and_raise(Captain::Crm::TwentyClient::Error, 'HTTP 500')

    expect { run }.not_to raise_error
  end
end
