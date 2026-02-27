class CreateCaptainReportSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_report_snapshots do |t|
      t.references :account, null: false, foreign_key: true
      t.references :captain_unit, null: true, foreign_key: true
      t.date :snapshot_date, null: false
      t.jsonb :data, null: false, default: {}

      t.timestamps
    end

    add_index :captain_report_snapshots,
              %i[captain_unit_id snapshot_date],
              unique: true,
              name: 'idx_captain_snapshots_unique_date'
    add_index :captain_report_snapshots, %i[account_id snapshot_date]
  end
end
