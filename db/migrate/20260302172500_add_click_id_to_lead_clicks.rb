class AddClickIdToLeadClicks < ActiveRecord::Migration[7.0]
  def change
    add_column :lead_clicks, :click_id, :string
  end
end
