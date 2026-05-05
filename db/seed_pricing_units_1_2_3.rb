# Seed pricing for units 1 (Hotel Recanto), 2 (PrimeAL), 3 (Qnn01) from
# scenario data. Units 4 (Dolce), 5 (Express), 6 (Prime Ceilândia) já têm.
#
# Idempotente. Roda quantas vezes quiser.
# rubocop:disable all

NOITES_DATA = {
  'standard' => {
    aliases: %w[standard comum], extra_person_starts_at: 3,
    prices: {
      '2h' => { 'mon_wed' => 40.0, 'thu_sun' => 50.0 },
      '3h' => { 'mon_wed' => 50.0, 'thu_sun' => 65.0 },
      '4h' => { 'mon_wed' => 60.0, 'thu_sun' => 80.0 },
      'pernoite_promo' => { 'mon_wed' => 100.0, 'thu_sun' => 150.0 },
      'diaria' => 170.0
    }
  },
  'luxo' => {
    aliases: ['luxo', 'classica', 'clássica'], extra_person_starts_at: 3,
    prices: {
      '2h' => 60.0, '3h' => 75.0, '4h' => 85.0,
      'pernoite_promo' => { 'mon_wed' => 130.0, 'thu_sun' => 160.0 },
      'diaria' => 190.0
    }
  },
  'hidromassagem' => {
    aliases: %w[hidro hidromassagem banheira spa jacuzzi], extra_person_starts_at: 3,
    prices: {
      '2h' => 110.0, '3h' => 120.0, '4h' => 150.0,
      'pernoite_promo' => 250.0, 'diaria' => 300.0
    }
  }
}.freeze

PRIME_DATA = {
  'stilo' => {
    aliases: %w[stilo estilo], extra_person_starts_at: 3,
    prices: {
      '1h'   => { 'mon_wed' => 40.0, 'thu_sun' => 50.0 },
      '2h'  => { 'mon_wed' => 60.0, 'thu_sun' => 70.0 },
      '3h'  => { 'mon_wed' => 70.0, 'thu_sun' => 80.0 },
      '4h'  => { 'mon_wed' => 75.0, 'thu_sun' => 85.0 },
      'pernoite_promo' => { 'mon_wed' => 130.0, 'thu_sun' => 150.0 },
      'pernoite_integral' => { 'mon_wed' => 150.0, 'thu_sun' => 170.0 },
      'diaria' => { 'mon_wed' => 160.0, 'thu_sun' => 180.0 }
    }
  },
  'alexa' => {
    aliases: %w[alexa], extra_person_starts_at: 3,
    prices: {
      '1h'   => { 'mon_wed' => 50.0, 'thu_sun' => 60.0 },
      '2h'  => { 'mon_wed' => 65.0, 'thu_sun' => 75.0 },
      '3h'  => { 'mon_wed' => 75.0, 'thu_sun' => 85.0 },
      '4h'  => { 'mon_wed' => 80.0, 'thu_sun' => 90.0 },
      'pernoite_promo' => { 'mon_wed' => 140.0, 'thu_sun' => 160.0 },
      'pernoite_integral' => { 'mon_wed' => 160.0, 'thu_sun' => 180.0 },
      'diaria' => { 'mon_wed' => 170.0, 'thu_sun' => 200.0 }
    }
  },
  'hidromassagem' => {
    aliases: %w[hidro hidromassagem banheira spa jacuzzi ofuro], extra_person_starts_at: 3,
    prices: {
      '1h'   => { 'mon_wed' => 130.0, 'thu_sun' => 140.0 },
      '2h'  => { 'mon_wed' => 150.0, 'thu_sun' => 160.0 },
      '3h'  => { 'mon_wed' => 170.0, 'thu_sun' => 180.0 },
      '4h'  => { 'mon_wed' => 190.0, 'thu_sun' => 200.0 },
      'pernoite_promo' => { 'mon_wed' => 260.0, 'thu_sun' => 280.0 },
      'pernoite_integral' => { 'mon_wed' => 280.0, 'thu_sun' => 300.0 },
      'diaria' => { 'mon_wed' => 350.0, 'thu_sun' => 370.0 }
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
    puts "✓ unit=#{unit.id} #{key}"
  end
end

# 1001 Noites brand units = 1 (Hotel Recanto), 3 (Qnn01)
[1, 3].each do |id|
  u = Captain::Unit.find(id)
  u.update!(extra_person_fee: 45.0, currency: 'BRL') if u.extra_person_fee.to_f.zero?
  upsert(u, NOITES_DATA)
end

# Prime brand unit = 2 (PrimeAL)
u = Captain::Unit.find(2)
u.update!(extra_person_fee: 0.0, currency: 'BRL')
upsert(u, PRIME_DATA)

puts "--- summary ---"
[1, 2, 3].each do |id|
  u = Captain::Unit.find(id)
  cats = u.pricing_categories.count
  amounts = Captain::PricingAmount.joins(:pricing_category).where(captain_pricing_categories: { captain_unit_id: u.id }).count
  puts "unit #{id} #{u.name}: cats=#{cats} amounts=#{amounts}"
end
# rubocop:enable all
