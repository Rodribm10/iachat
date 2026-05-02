class CreateCaptainPricingTables < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/MethodLength
  def change
    add_column :captain_units, :extra_person_fee, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :captain_units, :currency, :string, default: 'BRL', null: false

    create_table :captain_pricing_categories do |t|
      t.references :captain_unit, null: false, foreign_key: { to_table: :captain_units }
      t.string :key, null: false
      t.jsonb :aliases, null: false, default: []
      t.integer :extra_person_starts_at, null: false, default: 3
      t.timestamps
    end
    add_index :captain_pricing_categories, [:captain_unit_id, :key], unique: true

    create_table :captain_pricing_amounts do |t|
      t.references :captain_pricing_category, null: false, foreign_key: { to_table: :captain_pricing_categories }
      t.string :period, null: false
      t.string :day_bucket
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.timestamps
    end
    add_index :captain_pricing_amounts,
              [:captain_pricing_category_id, :period, :day_bucket],
              unique: true,
              name: 'idx_captain_pricing_amount_uniq'
  end
  # rubocop:enable Metrics/MethodLength
end
