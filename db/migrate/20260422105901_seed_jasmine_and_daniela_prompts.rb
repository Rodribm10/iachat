# Atualiza os prompts da Jasmine (orchestrator) e da Daniela (cenário reservas)
# com os conteúdos validados em staging (feat/retention-metrics + feat/captain-semantic-memory).
#
# Os arquivos de origem vivem em db/seed_prompts/ — eles são a fonte de verdade
# versionada desses prompts. Essa migration apenas sincroniza o banco com o
# conteúdo dos arquivos no momento do deploy.
#
# Idempotente: se os conteúdos já batem, não faz nada. Se divergirem, sobrescreve.
# Se preferir preservar um prompt custom em produção, não rode essa migration
# (marcar como skipped) ou ajuste os arquivos antes.
class SeedJasmineAndDanielaPrompts < ActiveRecord::Migration[7.1]
  def up
    return unless defined?(Captain::Assistant) && defined?(Captain::Scenario)

    update_jasmine
    update_daniela
  end

  def down
    # No-op: prompts não têm "versão anterior" canônica. Rollback manual se necessário.
  end

  private

  def update_jasmine
    path = Rails.root.join('db/seed_prompts/jasmine_orchestrator.md')
    return unless File.exist?(path)

    content = File.read(path)
    Captain::Assistant.where(name: 'Jasmine').find_each do |assistant|
      next if assistant.orchestrator_prompt == content

      assistant.update_columns(orchestrator_prompt: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      say_with_time "Updated Jasmine prompt on assistant ##{assistant.id}" do
        assistant.id
      end
    end
  end

  def update_daniela
    path = Rails.root.join('db/seed_prompts/daniela_reservas.md')
    return unless File.exist?(path)

    content = File.read(path)
    Captain::Scenario.where(title: 'Daniela_Reservas').find_each do |scenario|
      next if scenario.instruction == content

      scenario.update_columns(instruction: content, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      say_with_time "Updated Daniela prompt on scenario ##{scenario.id}" do
        scenario.id
      end
    end
  end
end
