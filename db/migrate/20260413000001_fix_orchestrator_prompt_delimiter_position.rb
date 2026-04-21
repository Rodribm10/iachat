class FixOrchestratorPromptDelimiterPosition < ActiveRecord::Migration[7.1]
  # Delimitador antigo (posição errada — depois de # Your Identity)
  OLD_DELIMITER = "\n# ---SECAO-ASSISTENTE---\n# Instruções Específicas deste Assistente".freeze
  # Texto correto sem delimitador naquela posição
  REPLACEMENT   = "\n\n# Instruções Específicas deste Assistente".freeze

  # Delimitador novo (posição correta — no final do template)
  END_MARKER_OLD = "- NUNCA tente responder via FAQ um pedido de foto ou imagem — sempre use handoff.\n# ---SECAO-ASSISTENTE---".freeze
  END_MARKER_OK  = "- NUNCA tente responder via FAQ um pedido de foto ou imagem — sempre use handoff.\n# ---SECAO-ASSISTENTE---".freeze

  def up
    # Corrige registros que têm o delimitador na posição errada (no meio do texto)
    Captain::Assistant.where('orchestrator_prompt LIKE ?', "%# ---SECAO-ASSISTENTE---\n# Instruções Específicas%").find_each do |assistant|
      fixed = assistant.orchestrator_prompt
                       .gsub("# ---SECAO-ASSISTENTE---\n# Instruções Específicas deste Assistente",
                             '# Instruções Específicas deste Assistente')

      # Garante que o delimitador existe no final, antes do conteúdo de instruções
      fixed = "#{fixed.rstrip}\n# ---SECAO-ASSISTENTE---\n" unless fixed.include?('# ---SECAO-ASSISTENTE---')

      assistant.update_column(:orchestrator_prompt, fixed) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
    # irreversível sem backup — não faz rollback
  end
end
