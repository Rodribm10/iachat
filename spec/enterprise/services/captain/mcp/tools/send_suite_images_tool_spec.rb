# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Mcp::Tools::SendSuiteImagesTool, type: :model do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:tool) { described_class.new }
  let!(:gallery_item) do
    create(
      :captain_gallery_item,
      :inbox_scoped,
      account: account,
      captain_unit: nil,
      inbox: conversation.inbox,
      suite_category: 'tabela-precos',
      suite_number: '01',
      description: 'Tabela de planos 2026. Envie quando o cliente perguntar preço.'
    )
  end

  def send_images
    tool.call(
      { 'conversation_id' => conversation.id, 'suite_category' => 'tabela-precos' },
      context: {}
    )
  end

  it 'envia a foto sem usar a descrição interna como legenda' do
    expect { send_images }.to change { conversation.messages.outgoing.count }.by(1)

    message = conversation.messages.outgoing.last
    expect(message.content).to be_blank
    expect(message.attachments.count).to eq(1)
  end

  it 'não cria mensagem nem confirma o envio quando o arquivo sumiu do storage' do
    gallery_item.image.blob.service.delete(gallery_item.image.blob.key)

    result = nil
    expect { result = send_images }.not_to(change { conversation.messages.outgoing.count })
    expect(result[:isError]).to be(true)
    expect(result[:content].first[:text]).to include('NÃO diga ao cliente')
  end
end
