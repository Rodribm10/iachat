require 'rails_helper'

describe Whatsapp::Providers::Wuzapi::PayloadParser do
  def build_payload(message)
    {
      'type' => 'Message',
      'phone_number' => '6140428064',
      'event' => {
        'Info' => {
          'ID' => 'ACDB58EDEE31F5E9B32C3C40A9F88D40',
          'IsFromMe' => false,
          'IsGroup' => false,
          'MediaType' => '',
          'PushName' => 'Julio',
          'Sender' => '124030233370795@lid',
          'SenderAlt' => '556199322739@s.whatsapp.net',
          'Timestamp' => '2026-08-15T17:55:56-03:00',
          'Type' => 'text'
        },
        'Message' => message
      }
    }
  end

  # Payload real capturado em produção: o WuzAPI manda Info.Type = "text" mesmo
  # quando o evento é só configuração de mensagem temporária do WhatsApp.
  let(:protocol_message) do
    {
      'messageContextInfo' => { 'deviceListMetadataVersion' => 2 },
      'protocolMessage' => {
        'disappearingMode' => { 'initiatedByMe' => true, 'initiator' => 1, 'trigger' => 2 },
        'ephemeralExpiration' => 7_776_000,
        'type' => 4
      }
    }
  end

  describe '#protocol_only?' do
    it 'returns true for a protocol-only payload' do
      parser = described_class.new(build_payload(protocol_message))

      expect(parser.protocol_only?).to be(true)
      expect(parser.message_type).to eq(:ignore)
      expect(parser.text_content).to be_nil
    end

    it 'returns false for a regular text message' do
      parser = described_class.new(build_payload({ 'conversation' => 'Oi, tem suíte livre?' }))

      expect(parser.protocol_only?).to be(false)
      expect(parser.message_type).to eq(:text)
      expect(parser.text_content).to eq('Oi, tem suíte livre?')
    end

    it 'returns false for an audio message without caption' do
      payload = build_payload({ 'audioMessage' => { 'URL' => 'https://mmg.whatsapp.net/audio.enc', 'mimetype' => 'audio/ogg; codecs=opus' } })
      payload['event']['Info']['Type'] = 'media'
      payload['event']['Info']['MediaType'] = 'audio'
      parser = described_class.new(payload)

      expect(parser.protocol_only?).to be(false)
      expect(parser.message_type).to eq(:audio)
    end

    it 'unwraps ephemeral wrappers before deciding' do
      parser = described_class.new(build_payload({ 'ephemeralMessage' => { 'message' => { 'conversation' => 'Bom dia' } } }))

      expect(parser.protocol_only?).to be(false)
      expect(parser.text_content).to eq('Bom dia')
    end
  end
end
