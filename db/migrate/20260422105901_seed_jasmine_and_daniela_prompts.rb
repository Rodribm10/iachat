# Sincroniza os prompts da Jasmine (orchestrator) e dos cenários
# (Daniela, Maria, Disponibilidade) com os arquivos versionados em
# db/seed_prompts/.
#
# Os arquivos de origem são a fonte de verdade. Esta migration apenas
# copia o conteúdo pros registros correspondentes. Roda toda vez que o
# timestamp da migration avança OU quando você chama manualmente via:
#   rails runner "Captain::PromptSync.run!"
#
# Convenções:
# - assistants/<slug>.md        → Captain::Assistant#orchestrator_prompt
# - scenarios/<slug>__<tit>.md  → Captain::Scenario#instruction (matched
#                                 by assistant name + scenario title)
#
# Mapeamentos em ASSISTANT_MAP / SCENARIO_TITLE_MAP.
# Idempotente: se o conteúdo já bate, pula (não atualiza updated_at).
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
    'maria_fotos' => 'maria_fotos'
  }.freeze

  def up
    return unless defined?(Captain::Assistant) && defined?(Captain::Scenario)

    sync_assistants
    sync_scenarios
  end

  def down
    # No-op: rollback manual se necessário.
  end

  private

  def sync_assistants
    Dir.glob(Rails.root.join('db/seed_prompts/assistants/*.md')).each do |path|
      slug = File.basename(path, '.md')
      assistant_name = ASSISTANT_MAP[slug]
      next if assistant_name.blank?

      content = File.read(path)
      Captain::Assistant.where(name: assistant_name).find_each do |assistant|
        next if assistant.orchestrator_prompt == content

        assistant.update_columns(orchestrator_prompt: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        say "Synced orchestrator prompt → #{assistant_name} (id=#{assistant.id}, #{content.size} chars)"
      end
    end
  end

  def sync_scenarios
    Dir.glob(Rails.root.join('db/seed_prompts/scenarios/*.md')).each do |path|
      filename = File.basename(path, '.md')
      assistant_slug, scenario_slug = filename.split('__', 2)

      assistant_name = ASSISTANT_MAP[assistant_slug]
      scenario_title = SCENARIO_TITLE_MAP[scenario_slug]
      next if assistant_name.blank? || scenario_title.blank?

      assistant_ids = Captain::Assistant.where(name: assistant_name).pluck(:id)
      next if assistant_ids.empty?

      content = File.read(path)
      Captain::Scenario.where(assistant_id: assistant_ids, title: scenario_title).find_each do |scenario|
        next if scenario.instruction == content

        scenario.update_columns(instruction: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        say "Synced scenario → #{assistant_name} / #{scenario_title} (id=#{scenario.id}, #{content.size} chars)"
      end
    end
  end
end
