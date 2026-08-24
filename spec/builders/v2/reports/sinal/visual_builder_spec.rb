require 'rails_helper'

RSpec.describe V2::Reports::Sinal::VisualBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:since) { 2.days.ago }
  let(:until_time) { 1.hour.from_now }
  let(:params) { { since: since, until: until_time, timezone_offset: '-3' } }
  let(:builder) { described_class.new(account, params) }

  def incoming!(conversation, created_at: Time.current)
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :incoming, created_at: created_at)
  end

  def ai_assistant
    @ai_assistant ||= create(:captain_assistant, account: account)
  end

  def ai_reply!(conversation, created_at: Time.current)
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :outgoing, sender: ai_assistant, created_at: created_at)
  end

  def panel_reply!(conversation, agent, created_at: Time.current)
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :outgoing, sender: agent, created_at: created_at)
  end

  # Eco real do provider (gowa): outgoing sem sender, mas com source_id — mesmo
  # "multi-device echo" já coberto em reactions_controller_spec.rb.
  def whatsapp_direct_reply!(conversation, created_at: Time.current, source_id: "GOWA:#{SecureRandom.hex(6)}")
    create(:message, :bot_message, account: account, conversation: conversation, inbox: inbox,
                                   created_at: created_at, source_id: source_id)
  end

  # Mesma forma sem autor, mas SEM source_id — lixo que não prova vir do
  # provider e não pode virar resposta humana.
  def authorless_reply!(conversation, created_at: Time.current)
    create(:message, :bot_message, account: account, conversation: conversation, inbox: inbox,
                                   created_at: created_at)
  end

  describe '#build' do
    describe 'service_modes' do
      it 'classifies ai-only, mixed and human-only conversations, folding WhatsApp-direct replies into "human"' do
        ai_only = create(:conversation, account: account, inbox: inbox)
        incoming!(ai_only)
        ai_reply!(ai_only)

        mixed_via_panel = create(:conversation, account: account, inbox: inbox)
        incoming!(mixed_via_panel)
        ai_reply!(mixed_via_panel)
        panel_reply!(mixed_via_panel, create(:user, account: account))

        mixed_via_whatsapp = create(:conversation, account: account, inbox: inbox)
        incoming!(mixed_via_whatsapp)
        ai_reply!(mixed_via_whatsapp)
        whatsapp_direct_reply!(mixed_via_whatsapp)

        human_only_panel = create(:conversation, account: account, inbox: inbox)
        incoming!(human_only_panel)
        panel_reply!(human_only_panel, create(:user, account: account))

        human_only_panel_and_whatsapp = create(:conversation, account: account, inbox: inbox)
        incoming!(human_only_panel_and_whatsapp)
        panel_reply!(human_only_panel_and_whatsapp, create(:user, account: account))
        whatsapp_direct_reply!(human_only_panel_and_whatsapp)

        human_only_whatsapp = create(:conversation, account: account, inbox: inbox)
        incoming!(human_only_whatsapp)
        whatsapp_direct_reply!(human_only_whatsapp)

        nobody_replied = create(:conversation, account: account, inbox: inbox)
        incoming!(nobody_replied)

        authorless_without_source_id = create(:conversation, account: account, inbox: inbox)
        incoming!(authorless_without_source_id)
        authorless_reply!(authorless_without_source_id)

        result = builder.build[:service_modes]

        expect(result).to eq(
          total: 8,
          ai_only: 1,
          mixed: 2,
          human_only: 3,
          unclassified: 2
        )
      end

      it 'does not count an authorless outgoing message without source_id as a WhatsApp-direct reply' do
        conversation = create(:conversation, account: account, inbox: inbox)
        incoming!(conversation)
        authorless_reply!(conversation)

        result = builder.build[:service_modes]

        expect(result[:human_only]).to eq(0)
        expect(result[:unclassified]).to eq(1)
      end
    end

    describe 'system_adoption' do
      it 'counts panel vs WhatsApp-direct replies and ranks agents by panel volume only' do
        agent_a = create(:user, account: account, name: 'Agente A')
        agent_b = create(:user, account: account, name: 'Agente B')
        conversation = create(:conversation, account: account, inbox: inbox)
        incoming!(conversation)
        panel_reply!(conversation, agent_a)
        panel_reply!(conversation, agent_a)
        panel_reply!(conversation, agent_b)
        whatsapp_direct_reply!(conversation)
        whatsapp_direct_reply!(conversation)
        whatsapp_direct_reply!(conversation)
        authorless_reply!(conversation)

        result = builder.build[:system_adoption]

        expect(result[:panel]).to eq(3)
        expect(result[:whatsapp_direct]).to eq(3)
        expect(result[:agents]).to eq(
          [
            { agent_id: agent_a.id, agent_name: 'Agente A', messages_sent: 2 },
            { agent_id: agent_b.id, agent_name: 'Agente B', messages_sent: 1 }
          ]
        )
      end

      it 'buckets replies by local hour (0-23) according to timezone_offset, split panel x WhatsApp-direct' do
        day_start = Time.utc(2026, 8, 24, 0, 0, 0)
        day_builder = described_class.new(account, { since: day_start, until: day_start + 1.day, timezone_offset: '-3' })
        conversation = create(:conversation, account: account, inbox: inbox)
        # 14:00 UTC - 3h = 11:00 local
        panel_reply!(conversation, create(:user, account: account), created_at: day_start + 14.hours)
        # 05:00 UTC - 3h = 02:00 local
        whatsapp_direct_reply!(conversation, created_at: day_start + 5.hours)

        hours = day_builder.build[:system_adoption][:hours]

        expect(hours.length).to eq(24)
        expect(hours.map { |h| h[:hour] }).to eq((0..23).to_a)
        expect(hours[11]).to eq(hour: 11, panel: 1, whatsapp_direct: 0)
        expect(hours[2]).to eq(hour: 2, panel: 0, whatsapp_direct: 1)
        expect(hours.sum { |h| h[:panel] }).to eq(1)
        expect(hours.sum { |h| h[:whatsapp_direct] }).to eq(1)
      end
    end
  end
end
