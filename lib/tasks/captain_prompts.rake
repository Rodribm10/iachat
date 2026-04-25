namespace :captain do
  desc 'Sincroniza prompts (Captain::Assistant#orchestrator_prompt e Captain::Scenario#instruction) com arquivos em db/seed_prompts/_modelos/'
  task sync_prompts: :environment do
    next if ENV['SKIP_CAPTAIN_PROMPT_SYNC'] == 'true'
    next unless defined?(Captain::Assistant) && defined?(Captain::Scenario)

    CaptainPromptSync.new.call
  end
end

class CaptainPromptSync
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

  def call
    sync_assistants
    sync_scenarios
  end

  private

  def sync_assistants
    Dir.glob(Rails.root.join('db/seed_prompts/_modelos/assistants/*.md')).each do |path|
      slug = File.basename(path, '.md')
      assistant_name = ASSISTANT_MAP[slug]
      next if assistant_name.blank?

      content = File.read(path)
      next if content.strip.empty?

      Captain::Assistant.where(name: assistant_name).find_each do |assistant|
        next if assistant.orchestrator_prompt == content

        assistant.update_columns(orchestrator_prompt: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        Rails.logger.info "[captain:sync_prompts] Synced orchestrator → #{assistant_name} (id=#{assistant.id}, #{content.size} chars)"
      end
    end
  end

  def sync_scenarios
    Dir.glob(Rails.root.join('db/seed_prompts/_modelos/scenarios/*.md')).each do |path|
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
      Rails.logger.info "[captain:sync_prompts] Synced scenario (all units) → #{assistant_name} / #{scenario_title} (id=#{scenario.id}, #{content.size} chars)"
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
      Rails.logger.info "[captain:sync_prompts] Synced scenario (unit-scoped) → #{assistant_name} / #{scenario_title} (id=#{scenario.id}, #{content.size} chars)"
    end
  end
end
