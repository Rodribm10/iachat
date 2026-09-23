class Captain::Hermes::KnownFactsCatalog
  CONFIG_PATH = Rails.root.join('config/captain_known_facts.yml').freeze

  class << self
    def profile(profile_name)
      profiles.fetch(profile_name.to_s, {})
    end

    def profiles
      @profiles ||= YAML.safe_load_file(CONFIG_PATH, aliases: true).fetch('profiles')
    end

    def reset!
      @profiles = nil
    end
  end
end
