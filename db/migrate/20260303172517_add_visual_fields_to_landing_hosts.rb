class AddVisualFieldsToLandingHosts < ActiveRecord::Migration[7.1]
  def change
    add_column :landing_hosts, :page_title, :string, default: 'Atendimento Express' unless column_exists?(:landing_hosts, :page_title)
    add_column :landing_hosts, :page_subtitle, :string, default: "Atendimento Imediato\nEntrada Discreta\nSem Burocracia" unless column_exists?(
      :landing_hosts, :page_subtitle
    )
    add_column :landing_hosts, :button_text, :string, default: 'Ver disponibilidade agora' unless column_exists?(:landing_hosts, :button_text)
    add_column :landing_hosts, :logo_url, :string unless column_exists?(:landing_hosts, :logo_url)
    add_column :landing_hosts, :suite_image_url, :string unless column_exists?(:landing_hosts, :suite_image_url)
    add_column :landing_hosts, :theme_color, :string, default: '#25D366' unless column_exists?(:landing_hosts, :theme_color)
    add_column :landing_hosts, :whatsapp_number, :string, default: '' unless column_exists?(:landing_hosts, :whatsapp_number)
  end
end
