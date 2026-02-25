# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Captain::Tools::SendSuiteImagesTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:brand) { create(:captain_brand, account: account) }
  let(:unit) do
    Captain::Unit.create!(
      account: account,
      brand: brand,
      inbox: conversation.inbox,
      name: 'Unidade Teste Tool',
      inter_pix_key: SecureRandom.uuid,
      inter_account_number: '12345678'
    )
  end
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) do
    Struct.new(:state).new(
      {
        account_id: account.id,
        conversation: { id: conversation.id }
      }
    )
  end

  before do
    create(:captain_inbox, captain_assistant: assistant, inbox: conversation.inbox, captain_unit: unit)
  end

  it 'sends inbox-scoped gallery images from the current conversation inbox' do
    create(
      :captain_gallery_item,
      :inbox_scoped,
      account: account,
      captain_unit: unit,
      inbox: conversation.inbox,
      suite_category: 'hidromassagem',
      suite_number: '101'
    )
    create(
      :captain_gallery_item,
      :inbox_scoped,
      account: account,
      captain_unit: unit,
      inbox: conversation.inbox,
      suite_category: 'hidromassagem',
      suite_number: '101'
    )

    result = nil
    expect do
      result = tool.execute(tool_context, suite_category: 'hidromassagem', suite_number: '101', limit: 2)
    end.to change { conversation.messages.outgoing.where(sender: assistant).count }.by(2)

    expect(result[:success]).to be(true)
    expect(result[:sent_count]).to eq(2)

    created_messages = conversation.messages.outgoing.where(sender: assistant).order(created_at: :desc).limit(2)
    expect(created_messages.all? { |message| message.attachments.any? }).to be(true)
  end

  it 'falls back to global gallery when there are no photos in the inbox scope' do
    create(
      :captain_gallery_item,
      account: account,
      scope: 'global',
      suite_category: 'hidromassagem',
      suite_number: '101'
    )

    result = nil
    expect do
      result = tool.execute(tool_context, suite_category: 'hidromassagem', suite_number: '101')
    end.to change { conversation.messages.outgoing.where(sender: assistant).count }.by(1)

    expect(result[:success]).to be(true)
    expect(result[:scope]).to eq('global')
  end

  it 'does not use photos from another inbox and returns a conversational message when nothing matches' do
    other_inbox = create(:inbox, account: account)
    other_unit = Captain::Unit.create!(
      account: account,
      brand: brand,
      inbox: other_inbox,
      name: 'Outra Unidade Teste Tool',
      inter_pix_key: SecureRandom.uuid,
      inter_account_number: '87654321'
    )
    create(
      :captain_gallery_item,
      :inbox_scoped,
      account: account,
      captain_unit: other_unit,
      inbox: other_inbox,
      suite_category: 'hidromassagem',
      suite_number: '101'
    )

    result = tool.execute(tool_context, suite_category: 'hidromassagem', suite_number: '101')

    expect(result[:success]).to be(true)
    expect(result[:formatted_message]).to match(/não encontrei fotos cadastradas/i)
  end
end
