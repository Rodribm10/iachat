require 'rails_helper'

describe Whatsapp::Providers::GowaService do
  subject(:service) { described_class.new(whatsapp_channel: channel) }

  let(:channel) do
    instance_double(
      Channel::Whatsapp,
      provider_config: { 'gowa_base_url' => 'https://gowa.example', 'gowa_device_id' => 'Device-1' },
      gowa_username: 'user',
      gowa_password: 'pass'
    )
  end
  let(:client) { instance_double(Gowa::Client) }

  before { allow(Gowa::Client).to receive(:new).and_return(client) }

  def build_message(content:, attributes:, in_reply_to_external_id: nil)
    instance_double(
      Message,
      id: 1,
      content: content,
      content_attributes: attributes,
      attachments: [],
      in_reply_to_external_id: in_reply_to_external_id
    )
  end

  describe '#toggle_typing_status' do
    # O listener entrega o nome do evento ('conversation.typing_on'). A checagem
    # antiga só reconhecia 'typing_on'/'on', então todo evento virava o valor de parada e
    # o "digitando…" nunca aparecia pro cliente. 'start'/'stop' são os valores que o GOWA
    # aceita em `action` (confirmado empiricamente) — 'composing'/'paused' é dialeto
    # wuzapi/whatsmeow e o GOWA rejeita com VALIDATION_ERROR.
    it 'traduz o nome do evento do listener em start' do
      expect(client).to receive(:send_presence).with('Device-1', '5561999999999', 'start')

      service.toggle_typing_status(Events::Types::CONVERSATION_TYPING_ON, recipient_id: '5561999999999')
    end

    it 'traduz o evento de parada em stop' do
      expect(client).to receive(:send_presence).with('Device-1', '5561999999999', 'stop')

      service.toggle_typing_status(Events::Types::CONVERSATION_TYPING_OFF, recipient_id: '5561999999999')
    end
  end

  describe '#send_message with a reaction' do
    # Antes desta rota, a mensagem de reacao caia no envio de texto normal e o
    # cliente recebia um "👍" solto como se fosse uma mensagem escrita.
    it 'reacts on the target message instead of sending the emoji as text' do
      message = build_message(content: '👍', attributes: { 'is_reaction' => true },
                              in_reply_to_external_id: 'GOWA:ABC123')

      expect(client).to receive(:send_reaction)
        .with('Device-1', '5561999999999', 'ABC123', '👍')
        .and_return({ 'results' => { 'id' => 'REACT1' } })
      expect(client).not_to receive(:send_text)

      expect(service.send_message('5561999999999', message)).to eq('GOWA:REACT1')
    end

    it 'skips the reaction when there is no target message' do
      message = build_message(content: '👍', attributes: { 'is_reaction' => true })

      expect(client).not_to receive(:send_reaction)
      expect(client).not_to receive(:send_text)

      expect(service.send_message('5561999999999', message)).to be_nil
    end

    it 'still sends a normal message as text' do
      message = build_message(content: 'bom dia', attributes: {})

      expect(client).to receive(:send_text).and_return({ 'results' => { 'id' => 'MSG1' } })
      expect(client).not_to receive(:send_reaction)

      expect(service.send_message('5561999999999', message)).to eq('GOWA:MSG1')
    end
  end
end
