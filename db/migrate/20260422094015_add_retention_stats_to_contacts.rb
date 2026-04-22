class AddRetentionStatsToContacts < ActiveRecord::Migration[7.1]
  # Desnormaliza estatísticas de retenção/recorrência no próprio contato.
  # Atualizado por Captain::ContactStats::RecalculateJob (diário) + hooks
  # incrementais quando conversa ou PixCharge muda de estado.
  #
  # Colunas:
  # - interactions_count: interações qualificadas (≥2 msg cliente + ≥2 msg Jasmine, gap 30h)
  # - one_shot_consultations_count: consultas ≥1+1 que não atingiram o limiar de qualificada
  # - first_interaction_at / last_interaction_at: range da presença do cliente
  # - pix_generated_count: quantos Pix foram gerados (sinal de intenção)
  # - reservations_paid_count: quantos Pix foram efetivamente pagos (reserva real)
  # - is_recurring: true se interactions_count >= 2
  # - days_since_last_interaction: materializado pra filtros rápidos sem funções em tempo real
  def change
    add_column :contacts, :interactions_count, :integer, default: 0, null: false
    add_column :contacts, :one_shot_consultations_count, :integer, default: 0, null: false
    add_column :contacts, :first_interaction_at, :datetime
    add_column :contacts, :last_interaction_at, :datetime
    add_column :contacts, :pix_generated_count, :integer, default: 0, null: false
    add_column :contacts, :reservations_paid_count, :integer, default: 0, null: false
    add_column :contacts, :is_recurring, :boolean, default: false, null: false
    add_column :contacts, :days_since_last_interaction, :integer

    add_index :contacts, :last_interaction_at
    add_index :contacts, :is_recurring
    add_index :contacts, :days_since_last_interaction
    add_index :contacts, %i[account_id is_recurring last_interaction_at], name: 'idx_contacts_account_recurring_last'
  end
end
