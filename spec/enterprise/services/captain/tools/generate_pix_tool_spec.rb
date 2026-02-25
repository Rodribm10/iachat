# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Tools::GeneratePixTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tool) { described_class.new(assistant) }

  before do
    conversation.contact.update!(
      name: 'Cliente Teste',
      custom_attributes: conversation.contact.custom_attributes.merge('cpf' => '12345678901')
    )
  end

  it 'accepts positional params hash without raising NoMethodError' do
    reservation = create_draft_reservation
    allow(tool).to receive(:generate_new_pix).and_return({ success: true })
    tool.instance_variable_set(:@conversation, conversation)

    expect { tool.execute({ amount: '140,00' }) }.not_to raise_error
    expect(tool).to have_received(:generate_new_pix).with(have_attributes(id: reservation.id), amount: 140.0)
  end

  it 'resolves conversation from tool context state' do
    create_draft_reservation
    allow(tool).to receive(:generate_new_pix).and_return({ success: true })
    tool_context = Struct.new(:state).new(
      {
        account_id: account.id,
        conversation: { id: conversation.id }
      }
    )

    result = tool.execute(tool_context, amount: '140,00')
    expect(result).to include(success: true)
  end

  it 'hydrates cpf and name from recent incoming messages when contact is incomplete' do
    create_draft_reservation
    allow(tool).to receive(:generate_new_pix).and_return({ success: true })

    conversation.contact.update!(name: '!@#123', custom_attributes: {})
    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: conversation.contact,
      message_type: :incoming,
      content_type: :text,
      content: "Nome : rodrigo borba machado\nCPF : 002.519.381-31\n\nUma pernoite"
    )

    tool.instance_variable_set(:@conversation, conversation)
    result = tool.execute({ amount: '140,00' })

    expect(result).to include(success: true)
    expect(tool).to have_received(:generate_new_pix).with(instance_of(Captain::Reservation), amount: 140.0)

    conversation.contact.reload
    expect(conversation.contact.custom_attributes['cpf']).to eq('00251938131')
    expect(conversation.contact.name).to eq('Rodrigo Borba Machado')
  end

  it 'asks for cpf conversationally when cpf is missing' do
    allow(tool).to receive(:generate_new_pix).and_return({ success: true })
    conversation.contact.update!(name: 'Cliente Teste', custom_attributes: {})
    tool.instance_variable_set(:@conversation, conversation)

    result = tool.execute({ amount: '140,00' })

    expect(result[:success]).to be(true)
    expect(result[:requires_input]).to be(true)
    expect(result[:missing_field]).to eq('cpf')
    expect(result[:formatted_message]).to match(/preciso do seu cpf com 11 dígitos/i)
    expect(tool).not_to have_received(:generate_new_pix)
  end

  it 'recognizes cpf when customer sends only 11 digits' do
    create_draft_reservation
    allow(tool).to receive(:generate_new_pix).and_return({ success: true })

    conversation.contact.update!(name: 'Cliente Teste', custom_attributes: {})
    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: conversation.contact,
      message_type: :incoming,
      content_type: :text,
      content: '00251938131'
    )

    tool.instance_variable_set(:@conversation, conversation)
    result = tool.execute({ amount: '140,00' })

    expect(result).to include(success: true)
    expect(tool).to have_received(:generate_new_pix).with(instance_of(Captain::Reservation), amount: 140.0)
    expect(conversation.contact.reload.custom_attributes['cpf']).to eq('00251938131')
  end

  it 'returns a graceful error when conversation cannot be resolved' do
    result = tool.execute(amount: '140,00')

    expect(result).to include(success: false)
    expect(result[:formatted_message]).to match(/não foi possível identificar a conversa/i)
  end

  it 'creates a draft reservation automatically from conversation history when needed' do
    allow(tool).to receive(:generate_new_pix).and_return({ success: true })
    tool.instance_variable_set(:@conversation, conversation)

    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: conversation.contact,
      message_type: :incoming,
      content_type: :text,
      content: 'Quero reservar a suíte stilo para 25/02/2026 por uma pernoite'
    )
    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: create(:user, account: account),
      message_type: :outgoing,
      content_type: :text,
      content: 'Perfeito! O valor total é R$ 130,00 e o sinal de 50% é R$ 65,00. Posso gerar o Pix?'
    )

    result = tool.execute

    expect(result).to include(success: true)
    expect(tool).to have_received(:generate_new_pix).with(instance_of(Captain::Reservation), amount: 65.0)

    created = Captain::Reservation.where(conversation_id: conversation.id, status: 'draft').order(created_at: :desc).first
    expect(created).to be_present
    expect(created.suite_identifier.downcase).to include('stilo')
    expect(created.total_amount.to_f).to eq(130.0)
    expect(created.metadata['deposit_amount'].to_f).to eq(65.0)
  end

  it 'handles ASCII-8BIT message content without crashing during reservation parsing' do
    allow(tool).to receive(:generate_new_pix).and_return({ success: true })
    tool.instance_variable_set(:@conversation, conversation)

    incoming_content = 'Quero reservar a suíte Alexa para amanhã em uma pernoite'.dup.force_encoding('ASCII-8BIT')
    outgoing_content = 'Perfeito! O valor total é R$ 220,00 e o sinal é R$ 110,00.'.dup.force_encoding('ASCII-8BIT')

    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: conversation.contact,
      message_type: :incoming,
      content_type: :text,
      content: incoming_content
    )
    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      sender: create(:user, account: account),
      message_type: :outgoing,
      content_type: :text,
      content: outgoing_content
    )

    result = tool.execute

    expect(result).to include(success: true)
    expect(tool).to have_received(:generate_new_pix).with(instance_of(Captain::Reservation), amount: 110.0)
  end

  it 'asks conversationally for missing reservation data when draft cannot be inferred' do
    allow(tool).to receive(:generate_new_pix).and_return({ success: true })
    tool.instance_variable_set(:@conversation, conversation)

    result = tool.execute(amount: '140,00')

    expect(result[:success]).to be(true)
    expect(result[:requires_input]).to be(true)
    expect(result[:missing_fields]).to include('suite', 'check_in')
    expect(result[:formatted_message]).to match(/suíte/i)
    expect(result[:formatted_message]).to match(/check-in/i)
    expect(tool).not_to have_received(:generate_new_pix)
  end

  it 'returns cpf follow-up when provider rejects cpf payload' do
    reservation = create_draft_reservation
    tool.instance_variable_set(:@conversation, conversation)

    cob_service = instance_double(Captain::Inter::CobService)
    allow(Captain::Inter::CobService).to receive(:new).with(instance_of(Captain::Reservation), amount: 140.0).and_return(cob_service)
    allow(cob_service).to receive(:call).and_raise(StandardError, 'CPF do pagador inválido')

    result = tool.execute(amount: '140,00')

    expect(result[:success]).to be(true)
    expect(result[:requires_input]).to be(true)
    expect(result[:missing_field]).to eq('cpf')
    expect(result[:formatted_message]).to match(/cpf com 11 dígitos/i)
    expect(reservation.reload.status).to eq('draft')
  end

  it 'handles binary provider error messages without raising encoding exceptions' do
    binary_error = StandardError.new('Login/senha invalido'.dup.force_encoding('ASCII-8BIT'))

    expect { tool.send(:map_pix_error_message, binary_error) }.not_to raise_error
    mapped = tool.send(:map_pix_error_message, binary_error)
    expect(mapped).to match(%r{login/senha inválidos}i)
  end

  it 'returns conversational message when provider auth fails' do
    create_draft_reservation
    tool.instance_variable_set(:@conversation, conversation)

    cob_service = instance_double(Captain::Inter::CobService)
    allow(Captain::Inter::CobService).to receive(:new).with(instance_of(Captain::Reservation), amount: 140.0).and_return(cob_service)
    allow(cob_service).to receive(:call).and_raise(StandardError, 'Login/senha invalido'.dup.force_encoding('ASCII-8BIT'))

    result = tool.execute(amount: '140,00')

    expect(result[:success]).to be(true)
    expect(result[:formatted_message]).to match(%r{login/senha inválidos}i)
  end

  it 'normalizes ASCII-8BIT pix payload in tool response to UTF-8' do
    reservation = create_draft_reservation
    binary_pix_code = "/spi/\xE7abc123".dup.force_encoding('ASCII-8BIT')
    sgid = instance_double(SignedGlobalID, to_s: 'signed-token')
    charge = instance_double(Captain::PixCharge, pix_copia_e_cola: binary_pix_code)

    allow(charge).to receive(:to_sgid).with(expires_in: 2.hours, purpose: :pix_payment).and_return(sgid)
    allow(Rails.application.routes.url_helpers).to receive(:short_payment_link_url).and_return('http://localhost:3000/p/signed-token')

    result = tool.send(:build_pix_response, charge, reservation, amount: 110.0, prefix: 'Pix gerado')

    expect(result[:success]).to be(true)
    expect(result[:raw_payload].encoding).to eq(Encoding::UTF_8)
    expect(result[:formatted_message].encoding).to eq(Encoding::UTF_8)
    expect(result[:raw_payload]).to start_with('00020101021226930014BR.GOV.BCB.PIX2571spi-qrcode.bancointer.com.br/spi/')
  end

  def create_draft_reservation
    Captain::Reservation.create!(
      account: account,
      inbox: conversation.inbox,
      contact: conversation.contact,
      contact_inbox: conversation.contact_inbox,
      conversation: conversation,
      suite_identifier: 'Suite 101',
      check_in_at: 1.day.from_now.change(hour: 19, min: 0, sec: 0),
      check_out_at: 2.days.from_now.change(hour: 12, min: 0, sec: 0),
      status: :draft,
      total_amount: 280.0,
      metadata: { deposit_amount: 140.0 }
    )
  end
end
