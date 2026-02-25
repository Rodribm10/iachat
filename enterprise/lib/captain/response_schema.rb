# TODO: Wrap the schema lib under ai-agents
# So we can extend it as Agents::Schema
class Captain::ResponseSchema < RubyLLM::Schema
  string :response, description: 'The message to send to the user'
  string :reasoning, description: "Agent's thought process"
  string :reaction_emoji,
         description: 'Optional. A single emoji to react naturally. Prefer greetings/farewells ' \
                      'and occasional moments only (~20% of normal turns max). Do NOT react ' \
                      'to every message. Default to empty string if no specific reaction is needed.'
end
