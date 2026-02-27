# Nota de Resolução - Editor de Prompt do Orquestrador

**Objetivo:** Permitir a edição do prompt do orquestrador do Capitão IA via interface administrativa.

**Contexto:** Anteriormente, o prompt era fixo no arquivo `.liquid`, exigindo novos builds para qualquer alteração.

**Passos realizados:**
1. Criada migração para adicionar `orchestrator_prompt` em `captain_assistants`.
2. Refatorado `Captain::PromptRenderer` para permitir a leitura de templates padrão.
3. Implementado `Agentable#default_orchestrator_prompt` e lógica de priorização no backend.
4. Criado componente Vue `OrchestratorPromptEditor` com validações e funcionalidade de reset.
5. Integrado o componente na tela de configurações do assistente.

**Arquivos principais alterados:**
- `enterprise/app/models/concerns/agentable.rb`
- `enterprise/lib/captain/prompt_renderer.rb`
- `app/javascript/dashboard/routes/dashboard/captain/assistants/settings/Settings.vue`
- `app/javascript/dashboard/components-next/captain/pageComponents/assistant/settings/OrchestratorPromptEditor.vue`

**Como validar:**
- Acessar configurações do assistente -> Prompt do Orquestrador.
- Alterar o texto, salvar e verificar se persiste.
- Resetar para o padrão e verificar se o texto original retorna.

**Como reverter:**
- Remover a coluna `orchestrator_prompt` do banco de dados e apagar o componente Vue.
