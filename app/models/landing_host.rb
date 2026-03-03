# == Schema Information
#
# Table name: landing_hosts
#
#  id               :bigint           not null, primary key
#  active           :boolean
#  auto_label       :string
#  button_text      :string           default("Ver disponibilidade agora")
#  custom_config    :jsonb
#  default_campanha :string
#  default_source   :string
#  hostname         :string
#  initial_message  :text
#  logo_url         :string
#  page_subtitle    :string           default("Atendimento Imediato\nEntrada Discreta\nSem Burocracia")
#  page_title       :string           default("Atendimento Express")
#  suite_image_url  :string
#  theme_color      :string           default("#25D366")
#  unit_code        :string
#  whatsapp_number  :string           default("")
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  inbox_id         :integer
#
# Indexes
#
#  index_landing_hosts_on_hostname  (hostname) UNIQUE
#
class LandingHost < ApplicationRecord
end
