# Saúde das conexões externas do Captain.
#
#   bundle exec rake captain:conexoes          # leitura humana
#   bundle exec rake captain:conexoes_json     # JSON para o OS Foco consumir
#
# Sai com código 1 quando há algo alertável, para servir de sonda em cron.
namespace :captain do
  desc 'Mostra a saúde das conexões externas do Captain (IA, Hermes, certificados, aprendizado)'
  task conexoes: :environment do
    icones = { 'ok' => '✓', 'alerta' => '!', 'critico' => '✗', 'indisponivel' => '?' }.freeze
    status = Captain::Health::ConexoesService.new.call

    puts
    puts "== Conexões do Captain — #{Time.zone.parse(status[:referencia]).strftime('%d/%m/%Y %H:%M')} =="
    puts

    status[:conexoes].each do |c|
      puts "#{icones.fetch(c[:status], '?')} #{c[:nome]}"
      puts "    #{c[:detalhe]}"
      puts "    → #{c[:acao]}" if c[:acao].present?
      puts
    end

    r = status[:resumo]
    puts "#{r[:ok]} ok · #{r[:alerta]} alerta · #{r[:critico]} crítico · #{r[:indisponivel]} indisponível"

    exit 1 if r[:alertaveis].positive?
  end

  desc 'Saúde das conexões do Captain em JSON (para sondas externas)'
  task conexoes_json: :environment do
    puts Captain::Health::ConexoesService.new.call.to_json
  end
end
