class AddInboxIdToCaptainConversationInsights < ActiveRecord::Migration[7.1]
  def up
    add_reference :captain_conversation_insights, :inbox, foreign_key: true, null: true

    # Remove índice antigo que causaria conflito com o novo índice composto
    remove_index :captain_conversation_insights, name: 'idx_captain_insights_unique_period'

    # Novo índice que permite análise por Unidade OU por Inbox
    add_index :captain_conversation_insights,
              %i[captain_unit_id inbox_id period_start period_end],
              unique: true,
              name: 'idx_captain_insights_on_unit_inbox_period'
  end

  def down
    remove_index :captain_conversation_insights, name: 'idx_captain_insights_on_unit_inbox_period'

    # Recria o índice original para tornar o rollback completo
    add_index :captain_conversation_insights,
              %i[captain_unit_id period_start period_end],
              unique: true,
              name: 'idx_captain_insights_unique_period'

    remove_reference :captain_conversation_insights, :inbox, foreign_key: true
  end
end
