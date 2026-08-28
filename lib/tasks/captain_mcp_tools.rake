namespace :captain do
  namespace :mcp_tools do
    desc 'Lista as ferramentas MCP efetivas de um Captain::Assistant'
    task :list, [:assistant_id] => :environment do |_task, args|
      assistant = Captain::Assistant.find(args.fetch(:assistant_id))
      context = { account_id: assistant.account_id, assistant_id: assistant.id }
      configured = assistant.config.key?('mcp_tool_allowlist') ? assistant.mcp_tool_allowlist : 'legado: todas'

      puts "Assistente: #{assistant.id} - #{assistant.name}"
      puts "Allowlist configurado: #{configured.inspect}"
      puts Captain::Mcp::ToolRegistry.allowed_tool_names(context: context).sort
    end

    desc 'Define o allowlist MCP. Uso: FERRAMENTAS=add_label,handoff bin/rails captain:mcp_tools:set[22]'
    task :set, [:assistant_id] => :environment do |_task, args|
      assistant = Captain::Assistant.find(args.fetch(:assistant_id))
      requested_names = ENV.fetch('FERRAMENTAS', '').split(',').map(&:strip).reject(&:blank?).uniq
      registered_names = Captain::Mcp::ToolRegistry::TOOLS.map(&:name)
      unknown_names = requested_names - registered_names

      abort "Ferramentas desconhecidas: #{unknown_names.join(', ')}" if unknown_names.any?

      assistant.update!(mcp_tool_allowlist: requested_names)
      puts "Allowlist MCP atualizado para o assistente #{assistant.id}: #{requested_names.join(', ')}"
    end

    desc 'Remove o allowlist MCP e restaura o comportamento legado do assistente'
    task :clear, [:assistant_id] => :environment do |_task, args|
      assistant = Captain::Assistant.find(args.fetch(:assistant_id))
      assistant.update!(config: assistant.config.except('mcp_tool_allowlist'))
      puts "Allowlist MCP removido do assistente #{assistant.id}"
    end
  end
end
