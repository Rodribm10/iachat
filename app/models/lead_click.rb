# == Schema Information
#
# Table name: lead_clicks
#
#  id              :bigint           not null, primary key
#  campanha        :string
#  hostname        :string
#  ip              :string
#  lp              :string
#  source          :string
#  status          :integer
#  user_agent      :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  click_id        :string
#  contact_id      :integer
#  conversation_id :integer
#  inbox_id        :integer
#
# Indexes
#
#  index_lead_clicks_on_inbox_id_and_ip_and_status_and_created_at  (inbox_id,ip,status,created_at)
#
class LeadClick < ApplicationRecord
  enum status: { clicked: 0, converted: 1 }

  belongs_to :inbox, optional: true
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true
end
