class AddProbationToCaptainAssistantResponses < ActiveRecord::Migration[7.1]
  def change
    add_column :captain_assistant_responses, :trial_until, :datetime
    add_column :captain_assistant_responses, :source, :string
    add_column :captain_assistant_responses, :triage_reason, :string
    add_column :captain_assistant_responses, :judge_verdict, :jsonb, default: {}
    add_column :captain_assistant_responses, :promoted_at, :datetime
    add_column :captain_assistant_responses, :retired_at, :datetime
    add_column :captain_assistant_responses, :retired_reason, :string

    add_index :captain_assistant_responses, :trial_until, where: 'trial_until IS NOT NULL',
                                                          name: 'idx_cap_asst_resp_on_trial_until'
    add_index :captain_assistant_responses, :source, name: 'idx_cap_asst_resp_on_source'
  end
end
