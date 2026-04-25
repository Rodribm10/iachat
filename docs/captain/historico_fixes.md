# Histórico de Fixes — Captain (Jasmines)

Registro cronológico das correções aplicadas nos prompts e infra do Captain (assistants Jasmine + cenários daniela_reservas, disponibilidade_suites, maria_fotos, outras_unidades, reclamacoes_ouvidoria).

## Pra que serve

- **Auditoria humana** — saber "o que mudou quando e por quê" sem precisar abrir 10 commits
- **Evitar retrabalho** — antes de propor mudança nova, conferir se o problema já tem fix aplicado
- **Defesa contra Captain Reviewer "burro de memória"** — quando o Reviewer abrir issue nova baseado em conversa antiga, comparar o `created_at` da conversa com a data do fix correspondente: se a conversa é anterior ao fix, o problema já está tratado
- **Base pra automatizar Nível 3 do Reviewer** — eventualmente o prompt do Reviewer pode ler este arquivo e filtrar conversas anteriores ao último fix relevante (ou usar `git log` direto, que é equivalente)

## Como ler

Cada fix é um bloco YAML no `## Fix N` com os campos:

| Campo | Descrição |
|---|---|
| `fix_id` | Slug único do fix (kebab-case + data) |
| `data` | ISO 8601 com timezone — momento do deploy em prod, não do commit |
| `commit` | Hash curto do commit no repo |
| `deploy` | Tag da imagem em prod (ex: `v100`) |
| `escopo` | Lista de unidades afetadas (`primeal`, `primevl`, `qnn01`, `express`, `dolce_amore`, ou `todas`) |
| `cenarios_afetados` | Lista de cenários (`daniela_reservas`, `maria_fotos`, etc) ou `infra` se for código |
| `problemas_corrigidos` | Lista em linguagem natural — chave pra dedup contra Reviewer |
| `conversas_de_origem` | IDs de conversas que serviram como evidência do bug |
| `keywords` | Termos curtos pra busca rápida |
| `status` | `aplicado` (em prod) / `revertido` / `superseded_por: <fix_id>` |

## Como adicionar fix novo

Quando aplicar correção que afeta comportamento da Jasmine, adiciona um `## Fix N+1` no fim do arquivo seguindo o template do último. Mantém ordem cronológica (mais novo no fim).

---

## Fix 1 — v99 (preços corretos Express/Qnn01 + sync automático)

```yaml
fix_id: precos-express-qnn01-sync-2026-04-25
data: 2026-04-25T10:38-03:00
commit: fc2663be2
deploy: v99
escopo: [express, qnn01]
cenarios_afetados: [daniela_reservas, disponibilidade_suites, maria_fotos]
infra:
  - rake_task: lib/tasks/captain_prompts.rake (nova) — captain:sync_prompts lê _modelos/ e atualiza DB
  - service_args: iachat_iachat_app args mudados pra "sh -c 'captain:sync_prompts && rails s'"
  - docs: docs/precos/ (tabelas oficiais por marca, consulta humana)
problemas_corrigidos:
  - Express não tinha Suítes Singles, Família, Singles Duplo no prompt
  - Express Master qui-dom estava como 4h R$85; correto é 5h R$85
  - Qnn01 prompt usava nome "Master" (correto é "Luxo")
  - Qnn01 listava "Pole Dance" e "12h" (não existem na unidade)
  - Qnn01 Hidromassagem em 2 tabelas duplicadas (correto é tabela única "todos os dias")
  - Drift histórico git → DB (resolvido estruturalmente: sync automático em todo deploy)
conversas_de_origem: [4565, 4536, 4521, 4513, 4519, 4514, 4497, 4505, 4453, 4366, 4412, 4411, 4400, 4402, 4378, 4376, 4365, 4372, 4267, 4258, 4248, 4224, 4216, 4259, 4218]
keywords: [tabela qui-dom ausente, master luxo, pole dance qnn01, 12h, singles familia, sync manual docker cp]
status: aplicado
notas: |
  Origem: Captain Review 2026-04-25 (issue ROD-14). Reviewer detectou padrões de bug REAIS no
  período 22-25/04, mas no momento da execução o prompt do PrimeAL/PrimeVL já tinha sido
  corrigido em sessão anterior (sync manual em 24/04). Express e Qnn01 ainda estavam com bugs
  e foram corrigidos neste fix. Bonus: passou a sincronizar git → DB automaticamente em todo
  deploy via captain:sync_prompts no boot do iachat_iachat_app.
```

## Fix 2 — v100 (comportamento humano + valores curto)

```yaml
fix_id: comportamento-humano-valores-curto-2026-04-25
data: 2026-04-25T13:59-03:00
commit: 6eb7f99ea
deploy: v100
escopo: [primeal, primevl, qnn01, express]
cenarios_afetados: [daniela_reservas]
problemas_corrigidos:
  - Jasmine alucinava "não tenho a tabela exata por horas aqui neste momento" (delata IA)
  - Jasmine pedia "qual dia?" quando cliente perguntou só "valor"/"valores" (deveria mostrar tabela completa direto)
  - Jasmine mencionava "tabela qui-dom/feriado" na resposta ao cliente (nome interno escapando)
  - Falta de regra explícita pra "se comportar como humana — não delatar que é IA"
  - Falta de proibições contra frases-trigger de IA ("vou consultar", "deixa eu olhar", "preciso verificar")
conversas_de_origem: [4498]  # Rayssa Lorranny / Jasmine PrimeAL / 2026-04-25 12:44
keywords: [comportamento humano, robô exposto, IA delatada, valores curto, tabela qui-dom na resposta, pergunta com pergunta]
status: aplicado
notas: |
  Origem: Rodrigo enviou print de conversa real Rayssa Lorranny / Jasmine PrimeAL (25/04 12:44)
  com 3 problemas concretos. Decisão: aplicar nas 4 unidades porque é problema COMPORTAMENTAL,
  não específico de marca (per memória feedback_prompt_scope_by_brand: "comportamento global,
  preços por marca"). Mudanças aplicadas em 4 daniela_reservas:
    1. Nova seção 🤖➡️👤 SE COMPORTE COMO HUMANA no topo (frases proibidas + exemplos humanos)
    2. Nova REGRA DE OURO — VALORES CURTO antes da seção B (cliente pergunta só preço sem
       especificar → manda tabela completa direto, nunca pergunta dia primeiro)
    3. 3 proibições novas em 🚫 Proibições (não dizer que não tem tabela, não mencionar
       "tabela qui-dom" na resposta, não responder pergunta com pergunta)
```
