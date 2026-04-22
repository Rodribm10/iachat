require 'rails_helper'

RSpec.describe Captain::ContactStats::InteractionCalculatorService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }

  def open_conversation(created_at: Time.current)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: created_at)
  end

  def msg(conversation, kind, content, at)
    attrs = { conversation: conversation, content: content, created_at: at }
    case kind
    when :customer
      create(:message, message_type: :incoming, sender: contact, **attrs)
    when :bot
      # Agent/user outgoing — qualifica como "Jasmine" pelo nosso critério
      user = create(:user, account: account)
      create(:message, message_type: :outgoing, sender: user, **attrs)
    when :system
      create(:message, message_type: :outgoing, sender: nil, **attrs)
    end
  end

  describe '#call' do
    it 'returns empty stats when there are no conversations' do
      expect(described_class.new(contact: contact).call).to include(
        interactions_count: 0, one_shot_consultations_count: 0, is_recurring: false
      )
    end

    it 'returns empty stats when contact is labelled equipe_interna' do
      contact.update!(label_list: 'equipe_interna')
      conv = open_conversation
      now = Time.current
      msg(conv, :customer, 'Oi bom dia', now)
      msg(conv, :bot, 'Oi, em que posso ajudar?', now + 1.minute)

      expect(described_class.new(contact: contact).call).to include(interactions_count: 0)
    end

    it 'counts a qualified interaction when there are >=2 msgs per side' do
      conv = open_conversation
      t = Time.current
      msg(conv, :customer, 'Oi bom dia',  t)
      msg(conv, :bot,      'Oi! Posso ajudar?', t + 1.minute)
      msg(conv, :customer, 'Qual preço da Stilo?', t + 2.minutes)
      msg(conv, :bot,      'Stilo pernoite R$ 140', t + 3.minutes)

      result = described_class.new(contact: contact).call
      expect(result[:interactions_count]).to eq(1)
      expect(result[:one_shot_consultations_count]).to eq(0)
      expect(result[:is_recurring]).to be(false)
    end

    it 'classifies 1+1 as one-shot consultation' do
      conv = open_conversation
      t = Time.current
      msg(conv, :customer, 'Quanto custa Alexa?', t)
      msg(conv, :bot, 'R$ 100 por 4hrs', t + 1.minute)

      result = described_class.new(contact: contact).call
      expect(result[:interactions_count]).to eq(0)
      expect(result[:one_shot_consultations_count]).to eq(1)
    end

    it 'ignores interactions where one side has no textual content' do
      conv = open_conversation
      t = Time.current
      msg(conv, :customer, '👍', t)              # emoji, não conta
      msg(conv, :customer, 'Oi', t + 5.minutes)  # < 2 letras → não conta
      msg(conv, :bot, 'R$ 100', t + 10.minutes)  # só dígitos, não conta

      result = described_class.new(contact: contact).call
      expect(result[:interactions_count]).to eq(0)
      expect(result[:one_shot_consultations_count]).to eq(0)
    end

    it 'groups msgs within 30h into the same interaction' do
      conv = open_conversation
      t = 2.days.ago

      msg(conv, :customer, 'Oi bom dia', t)
      msg(conv, :bot,      'Oi!', t + 5.minutes)
      msg(conv, :customer, 'Qual preço?', t + 25.hours)   # dentro da janela 30h
      msg(conv, :bot,      'R$ 140', t + 25.hours + 1.minute)

      result = described_class.new(contact: contact).call
      expect(result[:interactions_count]).to eq(1)
    end

    it 'opens a new interaction when gap > 30h' do
      conv1 = open_conversation(created_at: 3.days.ago)
      conv2 = open_conversation(created_at: 1.hour.ago)

      t1 = 3.days.ago
      msg(conv1, :customer, 'Oi bom dia', t1)
      msg(conv1, :bot,      'Oi!', t1 + 5.minutes)
      msg(conv1, :customer, 'Reservar hoje', t1 + 10.minutes)
      msg(conv1, :bot,      'Ok confirmo', t1 + 15.minutes)

      t2 = 1.hour.ago
      msg(conv2, :customer, 'Voltei pra marcar outra', t2)
      msg(conv2, :bot,      'Claro, qual data?', t2 + 5.minutes)
      msg(conv2, :customer, 'Sexta que vem', t2 + 10.minutes)
      msg(conv2, :bot,      'Anotado', t2 + 15.minutes)

      result = described_class.new(contact: contact).call
      expect(result[:interactions_count]).to eq(2)
      expect(result[:is_recurring]).to be(true)
    end
  end
end
