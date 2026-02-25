class RenameWuzapiTokens < ActiveRecord::Migration[7.0]
  def change
    rename_column :channel_whatsapp, :encrypted_wuzapi_user_token, :wuzapi_user_token
    rename_column :channel_whatsapp, :encrypted_wuzapi_user_token_iv, :wuzapi_user_token_iv
    rename_column :channel_whatsapp, :encrypted_wuzapi_admin_token, :wuzapi_admin_token
    rename_column :channel_whatsapp, :encrypted_wuzapi_admin_token_iv, :wuzapi_admin_token_iv
  end
end
