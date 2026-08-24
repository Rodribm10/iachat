require 'rails_helper'

RSpec.describe Captain::Quality::FlagServiceGapsJob, type: :job do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, phone_number: '+5561999990000', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { Inbox.find_by!(channel: whatsapp_channel) }
  let(:assistant) { Captain::Assistant.create!(account: account, name: 'Bot', description: 'assistente de teste', engine: 'captain_interno') }

  before do
    CaptainInbox.create!(captain_assistant: assistant, inbox: inbox)
  end

  # Status é setado via update_column (não no create!) porque
  # Conversation#determine_conversation_status (before_create) força
  # status: :pending sempre que a inbox tem bot ativo — exatamente o caso
  # de toda inbox conectada ao Captain/Hermes, que é o que este job mira.
  def build_conversation(contact:, status: :open, waiting_since: nil)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_column(:status, Conversation.statuses[status.to_s])
    conversation.update_column(:waiting_since, waiting_since)
    conversation.update_column(:last_activity_at, Time.current)
    # rubocop:enable Rails/SkipsModelValidations
    conversation
  end

  def add_message(conversation, type:, content: 'oi', private: false, created_at: Time.current)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: type, content: content, private: private, created_at: created_at)
  end

  describe '#perform' do
    let(:contact) { create(:contact, account: account) }

    context 'with cliente_aguardando e demora_critica (lidas de waiting_since)' do
      it 'marca cliente_aguardando quando waiting_since passou de 30 minutos' do
        conversation = build_conversation(contact: contact, waiting_since: 31.minutes.ago)

        described_class.perform_now

        expect(conversation.reload.label_list).to include('cliente_aguardando')
      end

      it 'não marca cliente_aguardando quando waiting_since está dentro de 30 minutos' do
        conversation = build_conversation(contact: contact, waiting_since: 10.minutes.ago)

        described_class.perform_now

        expect(conversation.reload.label_list).not_to include('cliente_aguardando')
      end

      it 'marca demora_critica quando waiting_since passou de 2 horas (cumulativa com cliente_aguardando)' do
        conversation = build_conversation(contact: contact, waiting_since: 3.hours.ago)

        described_class.perform_now

        expect(conversation.reload.label_list).to include('cliente_aguardando', 'demora_critica')
      end

      it 'remove as duas etiquetas quando a conversa deixa de estar aguardando (alguém respondeu)' do
        conversation = build_conversation(contact: contact, waiting_since: 3.hours.ago)
        described_class.perform_now
        expect(conversation.reload.label_list).to include('cliente_aguardando', 'demora_critica')

        # rubocop:disable Rails/SkipsModelValidations
        conversation.update_column(:waiting_since, nil)
        # rubocop:enable Rails/SkipsModelValidations
        described_class.perform_now

        labels = conversation.reload.label_list
        expect(labels).not_to include('cliente_aguardando')
        expect(labels).not_to include('demora_critica')
      end

      it 'ignora conversa resolved mesmo com waiting_since antigo' do
        conversation = build_conversation(contact: contact, status: :resolved, waiting_since: 3.hours.ago)

        described_class.perform_now

        expect(conversation.reload.label_list).to be_empty
      end

      it 'é idempotente: rodar duas vezes seguidas não duplica etiqueta nem label' do
        conversation = build_conversation(contact: contact, waiting_since: 3.hours.ago)

        described_class.perform_now
        described_class.perform_now

        labels = conversation.reload.label_list
        expect(labels.count('cliente_aguardando')).to eq(1)
        expect(labels.count('demora_critica')).to eq(1)
        expect(account.labels.where(title: 'cliente_aguardando').count).to eq(1)
      end
    end

    context 'with objecao_sem_resposta (lida das mensagens)' do
      it 'marca quando a última mensagem do cliente é uma objeção e ninguém respondeu depois' do
        conversation = build_conversation(contact: contact, waiting_since: 5.minutes.ago)
        add_message(conversation, type: 'incoming', content: 'Obrigada, não gostei', created_at: 10.minutes.ago)

        described_class.perform_now

        expect(conversation.reload.label_list).to include('objecao_sem_resposta')
      end

      it 'não marca quando houve resposta depois da objeção' do
        conversation = build_conversation(contact: contact, waiting_since: nil)
        add_message(conversation, type: 'incoming', content: 'Não gostei', created_at: 20.minutes.ago)
        add_message(conversation, type: 'outgoing', content: 'Deixa eu te explicar melhor', created_at: 10.minutes.ago)

        described_class.perform_now

        expect(conversation.reload.label_list).not_to include('objecao_sem_resposta')
      end

      it 'não remove objecao_sem_resposta numa execução posterior, mesmo respondida depois (registro histórico)' do
        conversation = build_conversation(contact: contact, waiting_since: 5.minutes.ago)
        add_message(conversation, type: 'incoming', content: 'Não gostei', created_at: 10.minutes.ago)
        described_class.perform_now
        expect(conversation.reload.label_list).to include('objecao_sem_resposta')

        add_message(conversation, type: 'outgoing', content: 'Consegui um desconto especial pra você', created_at: 1.minute.ago)
        described_class.perform_now

        expect(conversation.reload.label_list).to include('objecao_sem_resposta')
      end
    end

    context 'when a conversa é da própria conta consigo mesma' do
      it 'ignora conversa cujo contato é o próprio número do canal, mesmo qualificando pras outras regras' do
        self_contact = create(:contact, account: account, phone_number: whatsapp_channel.phone_number)
        conversation = build_conversation(contact: self_contact, waiting_since: 3.hours.ago)
        add_message(conversation, type: 'incoming', content: 'não gostei', created_at: 3.hours.ago)

        described_class.perform_now

        expect(conversation.reload.label_list).to be_empty
      end
    end
  end
end
