# Backfill one-time das tabelas de preço pra Dolce Amore (unit 4) e
# Express (unit 5) — copia o que estava hardcoded no PricingTables.rb
# antes da migração pra DB.
#
# Idempotente: roda find_or_create_by em tudo. Pode rodar várias vezes sem
# criar duplicata.
#
# Uso:
#   docker exec iachat_iachat_app bundle exec rails runner db/seed_pricing_tables.rb
#
# rubocop:disable all

# Garante extra_person_fee + currency configurados nas units
dolce = Captain::Unit.find(4)
dolce.update!(extra_person_fee: 45.0, currency: 'BRL') if dolce.extra_person_fee.to_f.zero?

express = Captain::Unit.find(5)
express.update!(extra_person_fee: 0.0, currency: 'BRL')

DOLCE_AMORE_DATA = {
  'apartamento' => {
    aliases: ['apto', 'standard', 'apartamento standard', 'apartamento_standard'],
    extra_person_starts_at: 3,
    prices: { '3h' => 85.0, 'pernoite_promo' => 110.0, 'pernoite_integral' => 155.0, 'diaria' => 290.0 }
  },
  'suite_master' => {
    aliases: ['master', 'suite master', 'suíte master', '2 andares'],
    extra_person_starts_at: 3,
    prices: { '3h' => 90.0, 'pernoite_promo' => 130.0, 'pernoite_integral' => 180.0, 'diaria' => 340.0 }
  },
  'suite_luxo' => {
    aliases: ['luxo', 'suite luxo', 'suíte luxo', 'classica', 'clássica'],
    extra_person_starts_at: 3,
    prices: { '3h' => 90.0, 'pernoite_promo' => 130.0, 'pernoite_integral' => 180.0, 'diaria' => 340.0 }
  },
  'suite_tematica' => {
    aliases: ['tematica', 'temática', 'suite tematica', 'suíte temática'],
    extra_person_starts_at: 3,
    prices: { '3h' => 90.0, 'pernoite_promo' => 130.0, 'pernoite_integral' => 180.0, 'diaria' => 340.0 }
  },
  'mini_chale_45' => {
    aliases: ['mini chale', 'mini chalé', 'chale 45', 'chalé 45', 'mini chalé 45', 'mini_chale'],
    extra_person_starts_at: 3,
    prices: { '3h' => 100.0, 'pernoite_promo' => 140.0, 'pernoite_integral' => 190.0, 'diaria' => 400.0 }
  },
  'chale_2_suites' => {
    aliases: ['chale 2', 'chalé 2', 'chale 2 suites', 'chalé 2 suítes', 'chale_2', '2 suites'],
    extra_person_starts_at: 4,
    prices: { '3h' => 165.0, 'pernoite_promo' => 240.0, 'pernoite_integral' => 350.0, 'diaria' => 490.0 }
  },
  'suite_ouro' => {
    aliases: ['ouro', 'suite ouro', 'suíte ouro'],
    extra_person_starts_at: 4,
    prices: { '3h' => 230.0, 'pernoite_promo' => 340.0, 'pernoite_integral' => 440.0, 'diaria' => 830.0 }
  },
  'chale_master_4_suites' => {
    aliases: ['chale master', 'chalé master', 'master 4 suites', 'chalé master 4 suítes', 'chale_master', '4 suites'],
    extra_person_starts_at: 8,
    prices: { '3h' => 360.0, 'pernoite_promo' => 510.0, 'pernoite_integral' => 580.0, 'diaria' => 1240.0 }
  }
}.freeze

EXPRESS_DATA = {
  'standard' => {
    aliases: %w[standard comum básica basica apartamento\ standard],
    extra_person_starts_at: 3,
    prices: {
      '2h' => { 'mon_wed' => 40.0, 'thu_sun' => 50.0 },
      '3h' => { 'mon_wed' => 50.0, 'thu_sun' => 65.0 },
      '4h' => { 'mon_wed' => 60.0, 'thu_sun' => 80.0 },
      'pernoite_promo' => { 'mon_wed' => 100.0, 'thu_sun' => 120.0 },
      'diaria' => 150.0
    }
  },
  'master' => {
    aliases: ['master', 'melhor', 'suite master', 'suíte master'],
    extra_person_starts_at: 3,
    prices: {
      '2h' => { 'mon_wed' => 50.0, 'thu_sun' => 60.0 },
      '3h' => { 'mon_wed' => 60.0, 'thu_sun' => 75.0 },
      '4h' => { 'mon_wed' => 70.0 },
      '5h' => { 'thu_sun' => 85.0 },
      'pernoite_promo' => { 'mon_wed' => 120.0, 'thu_sun' => 140.0 },
      'diaria' => 160.0
    }
  },
  'singles' => {
    aliases: %w[singles single sozinho],
    extra_person_starts_at: 99,
    prices: {
      'pernoite_promo' => { 'mon_wed' => 80.0, 'thu_sun' => 110.0 },
      'diaria' => 130.0
    }
  },
  'familia' => {
    aliases: %w[familia família familiar],
    extra_person_starts_at: 99,
    prices: {
      'pernoite_promo' => 160.0,
      'diaria' => 190.0
    }
  },
  'singles_duplo' => {
    aliases: ['singles duplo', 'singles_duplo', 'casal', 'duplo'],
    extra_person_starts_at: 99,
    prices: {
      'pernoite_promo' => { 'mon_wed' => 180.0, 'thu_sun' => 220.0 },
      'diaria' => 250.0
    }
  }
}.freeze

def upsert(unit, data)
  data.each do |key, attrs|
    cat = Captain::PricingCategory.find_or_initialize_by(captain_unit_id: unit.id, key: key)
    cat.aliases = attrs[:aliases]
    cat.extra_person_starts_at = attrs[:extra_person_starts_at]
    cat.save!

    attrs[:prices].each do |period, value|
      if value.is_a?(Hash)
        value.each do |bucket, amount|
          row = Captain::PricingAmount.find_or_initialize_by(
            captain_pricing_category_id: cat.id, period: period, day_bucket: bucket
          )
          row.amount = amount
          row.save!
        end
      else
        row = Captain::PricingAmount.find_or_initialize_by(
          captain_pricing_category_id: cat.id, period: period, day_bucket: nil
        )
        row.amount = value
        row.save!
      end
    end

    puts "✓ unit=#{unit.id} #{key} (#{attrs[:prices].size} periods)"
  end
end

upsert(dolce, DOLCE_AMORE_DATA)
upsert(express, EXPRESS_DATA)

puts "--- summary ---"
puts "dolce categories: #{dolce.pricing_categories.count}"
puts "dolce amounts:    #{Captain::PricingAmount.joins(:pricing_category).where(captain_pricing_categories: { captain_unit_id: dolce.id }).count}"
puts "express categories: #{express.pricing_categories.count}"
puts "express amounts:    #{Captain::PricingAmount.joins(:pricing_category).where(captain_pricing_categories: { captain_unit_id: express.id }).count}"
# rubocop:enable all
