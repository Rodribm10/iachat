require 'rails_helper'

RSpec.describe Captain::Hermes::ReplyContextBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'João da Silva') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:agent) { create(:user, account: account, name: 'Daniela') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def mensagem(sender:, tipo:, texto:)
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: tipo, sender: sender, content: texto)
  end

  def resposta_citando(citada)
    create(:message, conversation: conversation, account: account, inbox: inbox,
                     message_type: :incoming, sender: contact, content: 'quero esse',
                     content_attributes: { in_reply_to: citada.id })
  end

  def contexto(resposta)
    described_class.new(message: resposta, conversation: conversation).perform
  end

  # `available_name` existe em User, AgentBot e Captain::Assistant, mas NÃO em Contact.
  # Como citar a própria mensagem é o caso mais comum no WhatsApp, isso levantava
  # NoMethodError e derrubava o OutgoingJob: a mensagem nunca chegava ao Hermes e o
  # cliente ficava sem resposta. Foram 83 ocorrências em produção até 26/07/2026.
  describe 'quando o cliente cita a própria mensagem' do
    it 'não levanta erro' do
      citada = mensagem(sender: contact, tipo: :incoming, texto: 'qual o valor da suíte?')

      expect { contexto(resposta_citando(citada)) }.not_to raise_error
    end

    it 'usa o nome do contato como remetente da mensagem citada' do
      citada = mensagem(sender: contact, tipo: :incoming, texto: 'qual o valor da suíte?')

      snapshot = contexto(resposta_citando(citada))[:quoted_message]

      expect(snapshot[:sender_name]).to eq('João da Silva')
      expect(snapshot[:sender_label]).to eq('cliente')
    end
  end

  describe 'quando o cliente cita a mensagem de um atendente' do
    it 'usa o nome do atendente' do
      citada = mensagem(sender: agent, tipo: :outgoing, texto: 'a diária sai R$ 220')

      snapshot = contexto(resposta_citando(citada))[:quoted_message]

      expect(snapshot[:sender_name]).to eq(agent.available_name)
      expect(snapshot[:sender_label]).to eq('atendente/Hermes')
    end
  end

  describe 'quando a mensagem citada não tem remetente' do
    it 'devolve o contexto sem nome, sem quebrar' do
      citada = create(:message, :bot_message, conversation: conversation, account: account, inbox: inbox,
                                              content: 'mensagem do sistema')

      snapshot = contexto(resposta_citando(citada))[:quoted_message]

      expect(snapshot).to be_present
      expect(snapshot[:sender_name]).to be_nil
    end
  end

  describe 'quando não há citação' do
    it 'devolve nil' do
      simples = mensagem(sender: contact, tipo: :incoming, texto: 'oi')

      expect(contexto(simples)).to be_nil
    end
  end
end
