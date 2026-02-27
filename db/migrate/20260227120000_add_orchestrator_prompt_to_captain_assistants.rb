class AddOrchestratorPromptToCaptainAssistants < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_assistants, :orchestrator_prompt, :text
  end
end
