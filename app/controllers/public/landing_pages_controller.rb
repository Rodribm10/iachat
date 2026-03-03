class Public::LandingPagesController < PublicController
  layout false

  def show
    host = request.host.to_s.sub(/^www\./, '')
    @landing_host = LandingHost.find_by(hostname: host, active: true)

    # Fallback local para testes
    return unless Rails.env.development? && @landing_host.nil?

    @landing_host = LandingHost.first || LandingHost.new(
      page_title: 'Atendimento Express',
      page_subtitle: 'Clique e fale direto com a recepcao agora',
      whatsapp_number: '556136131003',
      initial_message: 'Ola! Tenho interesse.',
      theme_color: '#27c15b',
      logo_url: 'https://iachat.hoteis1001noites.com.br/assets/images/dashboard/captain/logo.svg',
      unit_code: 'express',
      default_source: 'direto',
      default_campanha: 'site'
    )
  end
end
