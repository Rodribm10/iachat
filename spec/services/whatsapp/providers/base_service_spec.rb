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
end
