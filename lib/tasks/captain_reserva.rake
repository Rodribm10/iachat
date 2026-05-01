namespace :captain do
  desc 'Provisiona/reconcilia 1 Captain::Unit em reserva_hotel.unidades (Supabase reserva-1001)'
  task :reprovision_unit_in_supabase, [:unit_id] => :environment do |_t, args|
    unit_id = args[:unit_id]
    abort 'uso: rake captain:reprovision_unit_in_supabase[<unit_id>]' if unit_id.blank?

    unit = Captain::Unit.find_by(id: unit_id)
    abort "Captain::Unit #{unit_id} não encontrada" if unit.blank?

    result = Captain::Reserva::ProvisionUnitInSupabaseService.new(unit: unit).perform
    if result[:success]
      puts "[OK] unit=#{unit.id} (#{unit.name}) -> supabase_unit=#{result[:supabase_unit_id]}"
    else
      puts "[ERRO] unit=#{unit.id} (#{unit.name}): #{result[:error]}"
      exit 1
    end
  end

  desc 'Reconcilia TODAS as Captain::Unit em reserva_hotel.unidades (idempotente)'
  task provision_all_units_in_supabase: :environment do
    units = Captain::Unit.includes(:brand).order(:id)
    puts "Reconciliando #{units.count} unidade(s)..."

    failures = 0
    units.each do |unit|
      result = Captain::Reserva::ProvisionUnitInSupabaseService.new(unit: unit).perform
      if result[:success]
        puts "  [OK] unit=#{unit.id} (#{unit.name}) -> #{result[:supabase_unit_id]}"
      else
        failures += 1
        puts "  [ERRO] unit=#{unit.id} (#{unit.name}): #{result[:error]}"
      end
    end

    puts "Done. #{units.count - failures}/#{units.count} OK."
    exit 1 if failures.positive?
  end
end
