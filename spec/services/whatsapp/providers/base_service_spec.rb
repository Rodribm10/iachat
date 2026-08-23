require 'rails_helper'

describe Whatsapp::Providers::BaseService do
  subject(:service) { described_class.new(whatsapp_channel: double) }

  describe '#normalize_whatsapp_markdown' do
    # Regressao: o editor rich text do dashboard grava negrito como `**texto**`
    # (markdown padrao). O WhatsApp usa asterisco simples, entao o cliente lia
    # literalmente `**Rodrigo**` no topo de cada mensagem assinada.
    it 'converts double asterisk bold into the single asterisk WhatsApp uses' do
      expect(service.normalize_whatsapp_markdown("**Rodrigo**\n\nbom dia"))
        .to eq("*Rodrigo*\n\nbom dia")
    end

    it 'converts every bold run in the message' do
      expect(service.normalize_whatsapp_markdown('**a** e **b**')).to eq('*a* e *b*')
    end

    it 'leaves text that is already single asterisk untouched' do
      expect(service.normalize_whatsapp_markdown('*Rodrigo*')).to eq('*Rodrigo*')
    end

    it 'leaves plain text untouched' do
      expect(service.normalize_whatsapp_markdown('bom dia')).to eq('bom dia')
    end

    it 'does not span line breaks' do
      expect(service.normalize_whatsapp_markdown("**a\nb**")).to eq("**a\nb**")
    end

    it 'returns blank content as is' do
      expect(service.normalize_whatsapp_markdown(nil)).to be_nil
      expect(service.normalize_whatsapp_markdown('')).to eq('')
    end
  end

  describe '#signature_name_for' do
    it 'uses the display_name when the User sender has one set' do
      user = User.new(name: 'Ana Paula', display_name: 'Ana')
      message = instance_double(Message, sender: user)

      expect(service.signature_name_for(message)).to eq('Ana')
    end

    it 'falls back to the User name when display_name is blank' do
      user = User.new(name: 'Ana Paula', display_name: nil)
      message = instance_double(Message, sender: user)

      expect(service.signature_name_for(message)).to eq('Ana Paula')
    end

    # Regressao: o Hermes grava o nome do assistente com um sufixo tecnico
    # interno (o motor por tras do atendimento) e isso vazou pro cliente, que
    # lia literalmente "*Bianca · H*" no topo da mensagem.
    it 'strips a "· H" technical suffix from a Captain::Assistant name' do
      assistant = Captain::Assistant.new(name: 'Bianca · H')
      message = instance_double(Message, sender: assistant)

      expect(service.signature_name_for(message)).to eq('Bianca')
    end

    it 'strips a "· Hermes" technical suffix from a Captain::Assistant name' do
      assistant = Captain::Assistant.new(name: 'Duda · Hermes')
      message = instance_double(Message, sender: assistant)

      expect(service.signature_name_for(message)).to eq('Duda')
    end

    it 'strips a ".H" technical suffix from a Captain::Assistant name' do
      assistant = Captain::Assistant.new(name: 'Lara.H')
      message = instance_double(Message, sender: assistant)

      expect(service.signature_name_for(message)).to eq('Lara')
    end

    it 'keeps a Captain::Assistant name whose suffix is not the technical marker' do
      assistant = Captain::Assistant.new(name: 'Sofia · Prime')
      message = instance_double(Message, sender: assistant)

      expect(service.signature_name_for(message)).to eq('Sofia · Prime')
    end

    it "falls back to the inbox's shift signature name for any other sender" do
      inbox = instance_double(Inbox, shift_signature_name: 'Equipe Noturna')
      message = instance_double(Message, sender: nil, inbox: inbox)

      expect(service.signature_name_for(message)).to eq('Equipe Noturna')
    end
  end

  describe '#content_with_signature' do
    let(:user) { User.new(name: 'Ana Paula', display_name: 'Ana') }

    it 'prefixes the normalized content with the sender name when the signature is enabled' do
      inbox = instance_double(Inbox, message_signature_enabled?: true)
      message = instance_double(Message, content: 'Bom dia', sender: user, inbox: inbox)

      expect(service.content_with_signature(message)).to eq("*Ana*\nBom dia")
    end

    it 'returns only the normalized content when the signature is disabled' do
      inbox = instance_double(Inbox, message_signature_enabled?: false)
      message = instance_double(Message, content: '**Bom dia**', sender: user, inbox: inbox)

      expect(service.content_with_signature(message)).to eq('*Bom dia*')
    end

    it 'returns only the content when the resolved name is blank' do
      inbox = instance_double(Inbox, message_signature_enabled?: true, shift_signature_name: nil)
      message = instance_double(Message, content: 'Bom dia', sender: nil, inbox: inbox)

      expect(service.content_with_signature(message)).to eq('Bom dia')
    end

    it 'normalizes double asterisk bold into single asterisk in the prefixed content' do
      inbox = instance_double(Inbox, message_signature_enabled?: true)
      message = instance_double(Message, content: '**urgente**', sender: user, inbox: inbox)

      expect(service.content_with_signature(message)).to eq("*Ana*\n*urgente*")
    end
  end
end
