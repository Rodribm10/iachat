class CreateCaptainGalleryItems < ActiveRecord::Migration[7.0]
  def change
    create_table :captain_gallery_items do |t|
      t.references :account, null: false, foreign_key: true
      t.references :captain_unit, null: false, foreign_key: { to_table: :captain_units }
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :suite_category, null: false
      t.string :suite_number, null: false
      t.text :description, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :captain_gallery_items, [:account_id, :captain_unit_id], name: 'index_captain_gallery_items_on_account_and_unit'
    add_index :captain_gallery_items, [:account_id, :suite_category], name: 'index_captain_gallery_items_on_account_and_category'
    add_index :captain_gallery_items, [:account_id, :suite_number], name: 'index_captain_gallery_items_on_account_and_suite_number'
  end
end
