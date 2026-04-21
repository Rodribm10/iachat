# rubocop:disable Metrics/BlockLength
namespace :captain do
  namespace :ceo_digest do
    desc 'Configura o CEO Digest (webhook do Mattermost) para uma conta. Uso: rake captain:ceo_digest:configure[1,https://mm...,#ceo]'
    task :configure, %i[account_id webhook_url channel] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      ceo_config = {
        'enabled' => true,
        'mattermost_webhook_url' => args[:webhook_url],
        'mattermost_channel' => args[:channel].presence
      }.compact
      account.update!(custom_attributes: account.custom_attributes.to_h.merge('ceo_digest' => ceo_config))
      puts "OK — conta ##{account.id} (#{account.name}) configurada:"
      puts account.custom_attributes['ceo_digest'].inspect
    end

    desc 'Desativa o CEO Digest para uma conta. Uso: rake captain:ceo_digest:disable[1]'
    task :disable, [:account_id] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      current = account.custom_attributes.to_h
      current['ceo_digest'] = (current['ceo_digest'] || {}).merge('enabled' => false)
      account.update!(custom_attributes: current)
      puts "OK — CEO Digest desativado para conta ##{account.id}."
    end

    desc 'Dispara o CEO Digest agora. Uso: rake captain:ceo_digest:deliver[1] ou captain:ceo_digest:deliver[1,2026-04-09,2026-04-15]'
    task :deliver, %i[account_id period_start period_end] => :environment do |_t, args|
      account_id = args[:account_id]&.to_i
      raise 'account_id é obrigatório' if account_id.blank?

      period_start = args[:period_start].presence && Date.parse(args[:period_start])
      period_end = args[:period_end].presence && Date.parse(args[:period_end])

      puts "Disparando CEO Digest para conta ##{account_id} (#{period_start || 'última semana'} a #{period_end || 'ontem'})..."
      Captain::Reports::CeoDigestJob.new.perform(account_id, period_start, period_end)
      puts 'Fim. Veja o log do Rails pra detalhes da entrega.'
    end

    desc 'Mostra um preview do digest no terminal, sem enviar. Uso: rake captain:ceo_digest:preview[1]'
    task :preview, %i[account_id period_start period_end] => :environment do |_t, args|
      account = Account.find(args[:account_id])
      period_end = (args[:period_end].presence && Date.parse(args[:period_end])) || Date.yesterday
      period_start = (args[:period_start].presence && Date.parse(args[:period_start])) || (period_end - 6.days)

      digest = Captain::Reports::CeoDigestService.new(
        account: account, period_start: period_start, period_end: period_end
      ).call
      puts JSON.pretty_generate(digest)
    end
  end
end
# rubocop:enable Metrics/BlockLength
