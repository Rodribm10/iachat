class CreateCaptainUnitInboxes < ActiveRecord::Migration[7.0]
  def up
    create_table :captain_unit_inboxes do |t|
      t.bigint :captain_unit_id, null: false
      t.bigint :inbox_id,        null: false
      t.timestamps
    end

    add_index :captain_unit_inboxes, [:captain_unit_id, :inbox_id], unique: true, name: 'index_captain_unit_inboxes_on_unit_and_inbox'
    add_index :captain_unit_inboxes, :inbox_id, name: 'index_captain_unit_inboxes_on_inbox_id'

    add_foreign_key :captain_unit_inboxes, :captain_units, column: :captain_unit_id, on_delete: :cascade
    add_foreign_key :captain_unit_inboxes, :inboxes, column: :inbox_id, on_delete: :cascade

    # Migra dados existentes: cada unit que já tinha inbox_id ganha um registro na pivot
    execute <<~SQL.squish
      INSERT INTO captain_unit_inboxes (captain_unit_id, inbox_id, created_at, updated_at)
      SELECT id, inbox_id, NOW(), NOW()
      FROM captain_units
      WHERE inbox_id IS NOT NULL
      ON CONFLICT DO NOTHING
    SQL

    # Zera a coluna antiga (mas não a remove — remoção fica para migration futura)
    execute 'UPDATE captain_units SET inbox_id = NULL WHERE inbox_id IS NOT NULL'
  end

  def down
    # Restaura o inbox_id da primeira linha da pivot (rollback best-effort)
    execute <<~SQL.squish
      UPDATE captain_units cu
      SET inbox_id = (
        SELECT cui.inbox_id
        FROM captain_unit_inboxes cui
        WHERE cui.captain_unit_id = cu.id
        ORDER BY cui.created_at
        LIMIT 1
      )
    SQL

    drop_table :captain_unit_inboxes
  end
end
