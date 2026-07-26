require 'rails_helper'

# Em 26/07/2026 o `schedule.yml` apontava para `Captain::Notifications::NotificationScannerJob`,
# uma classe que não existe no repositório. O cron rodava a cada 5 minutos e morria em toda
# execução: 8.243 jobs mortos acumulados no Sidekiq, entupindo o DeadSet e escondendo os erros
# que realmente importavam (falhas de envio das atendentes).
#
# Uma entrada órfã no schedule não quebra deploy nem teste — falha em silêncio, em produção,
# para sempre. Este teste existe para que isso não se repita.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'config/schedule.yml' do
  let(:schedule) { YAML.load_file(Rails.root.join('config/schedule.yml')) }

  before { Rails.application.eager_load! }

  it 'agenda pelo menos um job' do
    expect(schedule.size).to be_positive
  end

  it 'só referencia classes que existem de fato' do
    orfas = schedule.filter_map do |nome, config|
      klass = config['class']
      next if klass.blank?

      begin
        klass.constantize
        nil
      rescue NameError
        "#{nome} -> #{klass}"
      end
    end

    expect(orfas).to be_empty,
                     "Jobs agendados apontando para classes inexistentes:\n  #{orfas.join("\n  ")}\n\n" \
                     'Reponha a classe ou remova a entrada do schedule.yml — um cron órfão falha ' \
                     'silenciosamente em produção a cada execução.'
  end

  it 'define uma expressão cron para todo job agendado' do
    sem_cron = schedule.reject { |_nome, config| config['cron'].present? }.keys

    expect(sem_cron).to be_empty
  end
end
# rubocop:enable RSpec/DescribeClass
