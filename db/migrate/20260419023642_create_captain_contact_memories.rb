class CreateCaptainContactMemories < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :captain_contact_memories do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :memory_type, null: false
      t.text :content, null: false
      t.text :evidence, null: false
      t.float :confidence, null: false
      t.string :scope, null: false, default: 'global'
      t.vector :embedding, limit: 1536
      t.bigint :source_conversation_id
      t.bigint :source_unit_id
      t.bigint :source_inbox_id
      t.datetime :expires_at
      t.datetime :last_verified_at, null: false
      t.datetime :superseded_at
      t.bigint :superseded_by_id
      t.datetime :deleted_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :captain_contact_memories,
              [:account_id, :contact_id],
              where: 'deleted_at IS NULL AND superseded_at IS NULL',
              name: 'idx_ccm_recall'

    add_index :captain_contact_memories,
              [:source_unit_id, :memory_type, :created_at],
              name: 'idx_ccm_analytics'

    add_index :captain_contact_memories,
              :deleted_at,
              where: 'deleted_at IS NOT NULL',
              name: 'idx_ccm_hard_delete'

    add_index :captain_contact_memories,
              :superseded_by_id,
              where: 'superseded_at IS NOT NULL',
              name: 'idx_ccm_superseded'

    add_index :captain_contact_memories,
              :source_conversation_id,
              name: 'idx_ccm_source_conversation'

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE INDEX idx_ccm_embedding
          ON captain_contact_memories
          USING ivfflat (embedding vector_cosine_ops)
          WITH (lists = 100);
        SQL
      end

      dir.down do
        execute 'DROP INDEX IF EXISTS idx_ccm_embedding;'
      end
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
