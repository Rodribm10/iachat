class CreateLeadClicks < ActiveRecord::Migration[7.1]
  def change
    create_table :lead_clicks do |t|
      t.integer :inbox_id
      t.string :ip
      t.string :user_agent
      t.string :hostname
      t.string :source
      t.string :campanha
      t.string :lp
      t.integer :status
      t.integer :conversation_id
      t.integer :contact_id

      t.timestamps
    end

    add_index :lead_clicks, [:inbox_id, :ip, :status, :created_at]
  end
end
