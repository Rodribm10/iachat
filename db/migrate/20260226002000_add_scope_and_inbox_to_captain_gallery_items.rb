class AddScopeAndInboxToCaptainGalleryItems < ActiveRecord::Migration[7.0]
  def up
    add_column :captain_gallery_items, :scope, :string, null: false, default: 'inbox'
    add_reference :captain_gallery_items, :inbox, null: true, foreign_key: true

    add_index :captain_gallery_items, [:account_id, :inbox_id], name: 'index_captain_gallery_items_on_account_and_inbox'
    add_index :captain_gallery_items, [:account_id, :scope, :inbox_id],
              name: 'index_captain_gallery_items_on_account_scope_and_inbox'

    execute <<~SQL.squish
      UPDATE captain_gallery_items AS cgi
      SET inbox_id = COALESCE(cu.inbox_id, ci.inbox_id)
      FROM captain_units AS cu
      LEFT JOIN captain_inboxes AS ci ON ci.captain_unit_id = cu.id
      WHERE cgi.captain_unit_id = cu.id
        AND cgi.inbox_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE captain_gallery_items
      SET scope = 'global'
      WHERE inbox_id IS NULL
    SQL

    change_column_null :captain_gallery_items, :captain_unit_id, true
  end

  # rubocop:disable Metrics/MethodLength
  def down
    execute <<~SQL.squish
      UPDATE captain_gallery_items AS cgi
      SET captain_unit_id = ci.captain_unit_id
      FROM captain_inboxes AS ci
      WHERE cgi.captain_unit_id IS NULL
        AND cgi.inbox_id = ci.inbox_id
        AND ci.captain_unit_id IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE captain_gallery_items AS cgi
      SET captain_unit_id = fallback.id
      FROM LATERAL (
        SELECT id
        FROM captain_units cu
        WHERE cu.account_id = cgi.account_id
        ORDER BY cu.id ASC
        LIMIT 1
      ) AS fallback
      WHERE cgi.captain_unit_id IS NULL
    SQL

    execute <<~SQL.squish
      DELETE FROM captain_gallery_items
      WHERE captain_unit_id IS NULL
    SQL

    change_column_null :captain_gallery_items, :captain_unit_id, false

    remove_index :captain_gallery_items,
                 name: 'index_captain_gallery_items_on_account_scope_and_inbox',
                 if_exists: true
    remove_index :captain_gallery_items,
                 name: 'index_captain_gallery_items_on_account_and_inbox',
                 if_exists: true
    remove_reference :captain_gallery_items, :inbox, foreign_key: true
    remove_column :captain_gallery_items, :scope
  end
  # rubocop:enable Metrics/MethodLength
end
