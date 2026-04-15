# frozen_string_literal: true

class Captain::Lifecycle::Config < ApplicationRecord
  self.table_name = 'captain_lifecycle_configs'

  belongs_to :account
  belongs_to :opt_out_label, class_name: 'Label', optional: true

  validates :account_id, uniqueness: true
  validates :min_interval_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :pause_on_customer_reply_within_minutes, numericality: { greater_than_or_equal_to: 0 }

  def self.for_account(account)
    find_or_create_by!(account_id: account.id)
  end
end
