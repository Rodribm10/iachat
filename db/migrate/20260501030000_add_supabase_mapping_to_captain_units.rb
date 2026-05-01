class AddSupabaseMappingToCaptainUnits < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_units, :supabase_unit_id, :uuid
    add_column :captain_units, :supabase_tenant_id, :bigint, default: 1
    add_column :captain_units, :supabase_marca_id, :uuid

    add_index :captain_units, :supabase_unit_id, unique: true, where: 'supabase_unit_id IS NOT NULL'
  end
end
