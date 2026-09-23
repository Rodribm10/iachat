# Mantem tabelas oficiais versionadas e o banco sincronizados. O sync e
# idempotente: atualiza/inclui as linhas declaradas sem apagar categorias que
# possam ter sido cadastradas para outra finalidade no admin.
class Captain::PricingConfigSync
  CONFIG_PATH = Rails.root.join('config/captain_pricing_tables.yml').freeze

  def initialize(config: nil)
    @config = config || YAML.safe_load_file(CONFIG_PATH, aliases: true)
    @stats = { profiles: 0, categories: 0, amounts: 0, skipped: [] }
  end

  def call
    @config.fetch('profiles', {}).each { |profile, data| sync_profile(profile, data) }
    log_summary
    @stats
  end

  private

  def sync_profile(profile, data)
    assistant = Captain::Assistant.find_by(engine: 'hermes', hermes_profile_name: profile)
    unit = assistant&.captain_unit
    return skip(profile, 'assistant/unidade não encontrado') if unit.blank?

    Captain::PricingCategory.transaction do
      data.fetch('categories', {}).each { |key, category| sync_category(unit, key, category) }
    end
    @stats[:profiles] += 1
  end

  def sync_category(unit, key, data)
    category = Captain::PricingCategory.find_or_initialize_by(captain_unit: unit, key: key)
    category.aliases = data.fetch('aliases', [])
    category.extra_person_starts_at = data.fetch('extra_person_starts_at', 3)
    category.save!
    @stats[:categories] += 1

    data.fetch('amounts', {}).each { |period, value| sync_amounts(category, period, value) }
  end

  def sync_amounts(category, period, value)
    amounts = value.is_a?(Hash) ? value : { nil => value }
    amounts.each do |bucket, amount|
      day_bucket = bucket.presence
      row = Captain::PricingAmount.find_or_initialize_by(
        pricing_category: category,
        period: period,
        day_bucket: day_bucket
      )
      row.amount = amount
      row.save!
      @stats[:amounts] += 1
    end
  end

  def skip(profile, reason)
    @stats[:skipped] << profile
    Rails.logger.warn("[captain:pricing_sync] #{profile}: #{reason}")
  end

  def log_summary
    Rails.logger.info(
      "[captain:pricing_sync] profiles=#{@stats[:profiles]} categories=#{@stats[:categories]} " \
      "amounts=#{@stats[:amounts]} skipped=#{@stats[:skipped].join(',')}"
    )
  end
end
