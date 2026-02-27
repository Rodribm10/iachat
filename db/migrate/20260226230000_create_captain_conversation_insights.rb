class CreateCaptainConversationInsights < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_conversation_insights do |t|
      t.references :account, null: false, foreign_key: true
      t.references :captain_unit, null: true, foreign_key: true
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :status, null: false, default: 'pending'
      t.jsonb :payload
      t.integer :conversations_count, default: 0
      t.integer :messages_count, default: 0
      t.integer :llm_tokens_used
      t.timestamp :generated_at

      t.timestamps
    end

    add_index :captain_conversation_insights,
              %i[captain_unit_id period_start period_end],
              unique: true,
              name: 'idx_captain_insights_unique_period'
    add_index :captain_conversation_insights, %i[account_id status]
  end
end
