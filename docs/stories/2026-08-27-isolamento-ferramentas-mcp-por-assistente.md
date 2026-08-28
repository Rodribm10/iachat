# Story: isolamento de ferramentas MCP por assistente

## Problema

O registry MCP do Captain expõe hoje todas as ferramentas registradas para todos os perfis Hermes. Com isso, a Duda recebe ferramentas exclusivas da operação hoteleira, como disponibilidade de suítes, PIX e reservas, mesmo sem precisar delas.

Não haverá migração da Duda para outro projeto. A implementação adapta somente o padrão útil de ferramentas por agente observado no projeto público [fazer-ai/agents](https://github.com/fazer-ai/agents#-ferramentas-e-conhecimento), preservando FAQs, labels, handoff, memória e integrações atuais.

## Resultado esperado

Cada `Captain::Assistant` pode definir em `config.mcp_tool_allowlist` a lista exata de ferramentas MCP disponíveis. A política vale para descoberta e execução:

- `tools/list` retorna apenas as ferramentas permitidas;
- `tools/call` rejeita uma ferramenta registrada, mas não permitida;
- assistentes sem a nova configuração mantêm todas as ferramentas atuais;
- contexto com `assistant_id` ou `inbox_id` inválido não recebe ferramentas;
- a configuração pode ser inspecionada e alterada por CLI antes de existir uma tela.

## Critérios de aceitação

- [x] O allowlist fica no `config` JSONB do assistente, sem migration de banco.
- [x] O assistente é resolvido por `assistant_id` e, como fallback, por `inbox_id`, respeitando `account_id` quando informado.
- [x] Ausência de identidade no contexto mantém o comportamento legado.
- [x] Identidade informada e inválida falha de forma fechada.
- [x] Ausência da chave `mcp_tool_allowlist` no assistente mantém compatibilidade total.
- [x] Allowlist vazio expõe zero ferramentas.
- [x] Nomes desconhecidos não são expostos nem executados.
- [x] O validador Hermes verifica a lista efetiva do assistente, sem exigir ferramentas hoteleiras de um agente configurado com allowlist.
- [x] Specs cobrem compatibilidade, isolamento por assistente, fallback por inbox e bloqueio na execução.

## Fontes técnicas

- O MCP separa descoberta (`tools/list`) e execução (`tools/call`) e exige controles de acesso adequados: [especificação oficial MCP](https://modelcontextprotocol.io/specification/2025-06-18/server/tools).
- Em PostgreSQL JSONB, Rails recomenda `store_accessor` sem serialização adicional: [Rails 7.2 ActiveRecord::Store](https://api.rubyonrails.org/v7.2/classes/ActiveRecord/Store.html).

## Fora do escopo desta story

- alterar prompt, FAQs ou regras comerciais da Duda;
- migrar a Duda para o runtime TypeScript do projeto público;
- agenda, follow-up, memória durável e debounce distribuído;
- criar a interface visual do allowlist;
- aplicar a configuração em produção.

## Próximas capacidades candidatas

1. debounce durável com agrupamento de mensagens;
2. follow-up em múltiplas etapas com cancelamento por resposta;
3. agenda, confirmação e lembrete;
4. trilha operacional por estágio, falhas e reprocessamento;
5. memória estruturada por contato com política de retenção.

## Aplicação planejada na Duda

Após o código chegar à V2, o allowlist inicial recomendado para a Duda é:

```text
add_label,handoff,faq_lookup,update_contact,get_contact_history,react_to_message,criar_nota_interna
```

Aplicação via CLI, sem alterar os demais campos do assistente:

```bash
FERRAMENTAS=add_label,handoff,faq_lookup,update_contact,get_contact_history,react_to_message,criar_nota_interna \
  bin/rails captain:mcp_tools:set[22]
```

Antes de ativar, confirmar que o profile da Duda envia `X-Captain-Assistant-Id: '22'` no MCP e executar `bin/hermes-validate zelo_atendente --json`.

## Validação

- [x] Specs focadas dos serviços MCP: 14 exemplos, 0 falhas.
- [x] Spec da API confirma atualização parcial sem apagar o restante do config.
- [x] RuboCop nos 11 arquivos Ruby alterados: nenhuma ofensa.
- [x] `bash -n` e compilação do Ruby embutido em `bin/hermes-validate`.
- [x] Revisão do diff e verificação de arquivos sensíveis antes do commit.

## Arquivos alterados

- [x] `docs/stories/2026-08-27-isolamento-ferramentas-mcp-por-assistente.md`
- [x] `enterprise/app/services/captain/mcp/tool_policy.rb`
- [x] `enterprise/app/services/captain/mcp/tool_registry.rb`
- [x] `enterprise/app/services/captain/mcp/server.rb`
- [x] `enterprise/app/models/captain/assistant.rb`
- [x] `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb`
- [x] `enterprise/app/services/hermes_builder/validator.rb`
- [x] `lib/tasks/captain_mcp_tools.rake`
- [x] `bin/hermes-validate`
- [x] `spec/enterprise/services/captain/mcp/tool_policy_spec.rb`
- [x] `spec/enterprise/services/captain/mcp/tool_registry_spec.rb`
- [x] `spec/enterprise/services/captain/mcp/server_spec.rb`
- [x] `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb`
