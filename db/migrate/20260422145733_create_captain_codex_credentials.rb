class CreateCaptainCodexCredentials < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_codex_credentials do |t|
      t.text :access_token, null: false
      t.text :refresh_token, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_refresh_at
      t.string :chatgpt_account_id
      t.string :chatgpt_plan_type
      t.string :email
      t.string :status, null: false, default: 'active'
      t.timestamps
    end

    add_index :captain_codex_credentials, :status
    add_index :captain_codex_credentials, :expires_at
  end
end
