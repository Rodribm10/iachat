class AddTypingDelayToInboxes < ActiveRecord::Migration[7.0]
  def change
    add_column :inboxes, :typing_delay, :integer, default: 0
  end
end
