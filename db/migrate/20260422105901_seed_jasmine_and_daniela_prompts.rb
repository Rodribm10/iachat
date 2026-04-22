# Sincroniza os prompts da Jasmine (orchestrator) e dos cenários
# (Daniela, Maria, Disponibilidade, etc) com os arquivos versionados em
# db/seed_prompts/target/. Esses são a fonte de verdade — esta migration
# apenas espelha o conteúdo nos registros do DB.
#
# Convenções:
# - target/assistants/<slug>.md
#     → Captain::Assistant#orchestrator_prompt onde name == ASSISTANT_MAP[slug]
# - target/scenarios/<slug>.md
#     → Captain::Scenario#instruction onde title == SCENARIO_TITLE_MAP[slug]
#       (aplica em TODAS as unidades)
# - target/scenarios/<assistant_slug>__<scenario_slug>.md
#     → mesmo que o anterior, mas restrito ao assistant_slug — sobrescreve
#       o arquivo genérico só pra aquela unidade
#
# Idempotente: pula se conteúdo já bate. Arquivos vazios são ignorados.
class SeedJasmineAndDanielaPrompts < ActiveRecord::Migration[7.1]
  ASSISTANT_MAP = {
    'jasmine_qnn01' => 'Jasmine( Qnn01)',
    'jasmine_primeal' => 'Jasmine(PrimeAL)',
    'jasmine_primevl' => 'Jasmine(PrimeVL)',
    'jasmine_express' => 'Jasmine (Express)'
  }.freeze

  SCENARIO_TITLE_MAP = {
    'daniela_reservas' => 'Daniela_Reservas',
    'disponibilidade_suites' => 'Disponibilidade de suites',
    'maria_fotos' => 'maria_fotos',
    'outras_unidades' => 'outras_unidades',
    'reclamacoes_ouvidoria' => 'Reclamacoes_Ouvidoria'
  }.freeze

  def up
    return unless defined?(Captain::Assistant) && defined?(Captain::Scenario)

    sync_assistants
    sync_scenarios
  end

  def down
    # No-op. Rollback manual se necessário.
  end

  private

  def sync_assistants
    Dir.glob(Rails.root.join('db/seed_prompts/target/assistants/*.md')).each do |path|
      slug = File.basename(path, '.md')
      assistant_name = ASSISTANT_MAP[slug]
      next if assistant_name.blank?

      content = File.read(path)
      next if content.strip.empty?

      Captain::Assistant.where(name: assistant_name).find_each do |assistant|
        next if assistant.orchestrator_prompt == content

        assistant.update_columns(orchestrator_prompt: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        say "Synced orchestrator prompt → #{assistant_name} (id=#{assistant.id}, #{content.size} chars)"
      end
    end
  end

  def sync_scenarios
    Dir.glob(Rails.root.join('db/seed_prompts/target/scenarios/*.md')).each do |path|
      filename = File.basename(path, '.md')
      content = File.read(path)
      next if content.strip.empty?

      if filename.include?('__')
        apply_unit_scoped_scenario(filename, content)
      else
        apply_generic_scenario(filename, content)
      end
    end
  end

  def apply_generic_scenario(slug, content)
    scenario_title = SCENARIO_TITLE_MAP[slug]
    return if scenario_title.blank?

    Captain::Scenario.where(title: scenario_title).find_each do |scenario|
      next if scenario.instruction == content

      scenario.update_columns(instruction: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      assistant_name = scenario.assistant&.name
      say "Synced scenario (all units) → #{assistant_name} / #{scenario_title} (id=#{scenario.id}, #{content.size} chars)"
    end
  end

  def apply_unit_scoped_scenario(filename, content)
    assistant_slug, scenario_slug = filename.split('__', 2)
    assistant_name = ASSISTANT_MAP[assistant_slug]
    scenario_title = SCENARIO_TITLE_MAP[scenario_slug]
    return if assistant_name.blank? || scenario_title.blank?

    assistant_ids = Captain::Assistant.where(name: assistant_name).pluck(:id)
    return if assistant_ids.empty?

    Captain::Scenario.where(assistant_id: assistant_ids, title: scenario_title).find_each do |scenario|
      next if scenario.instruction == content

      scenario.update_columns(instruction: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      say "Synced scenario (unit-scoped) → #{assistant_name} / #{scenario_title} (id=#{scenario.id}, #{content.size} chars)"
    end
  end
end
