# Captain — prompts versionados

Source of truth dos prompts da Jasmine (orchestrator) e dos cenários
(Daniela, Maria, Disponibilidade) de cada unidade. O DB é apenas espelho:
a migration `20260422105901_seed_jasmine_and_daniela_prompts` sincroniza
o conteúdo destes arquivos para `captain_assistants.orchestrator_prompt`
e `captain_scenarios.instruction` no deploy.

## Convenção de nomes

Os nomes de arquivo batem com os `name` e `title` no banco:
- `assistants/<assistant_slug>.md` — aplicado em `captain_assistants.name = "<nome original>"`
- `scenarios/<assistant_slug>__<scenario_slug>.md` — aplicado em
  `captain_scenarios` filtrando por `assistant_id` (via nome) + `title`

### Mapeamento slug ↔ registro no DB

| Slug do arquivo | Assistant.name no DB |
|---|---|
| `jasmine_qnn01`   | `Jasmine( Qnn01)`   |
| `jasmine_primeal` | `Jasmine(PrimeAL)`  |
| `jasmine_primevl` | `Jasmine(PrimeVL)`  |
| `jasmine_express` | `Jasmine (Express)` |

| Slug do cenário         | Scenario.title no DB        |
|---|---|
| `daniela_reservas`        | `Daniela_Reservas`          |
| `disponibilidade_suites`  | `Disponibilidade de suites` |
| `maria_fotos`             | `maria_fotos`               |

## Workflow de edição

1. Edite o `.md` aqui no repo.
2. Abra PR com a mudança.
3. Merge → deploy → migration aplica no DB automaticamente.

Evite editar pelo painel do Chatwoot em produção — o próximo deploy
vai sobrescrever. Se precisar testar algo rápido, edita no painel E
atualiza o `.md` aqui depois pra manter sincronia.

## Inventário atual (snapshot de prod em 2026-04-22)

- 4 assistants (Jasmines) — um por unidade
- 12 scenarios (3 cenários x 4 assistants)

`jasmine_express.md` está vazio em prod — Express usa o template
default do repo (`enterprise/lib/captain/prompts/assistant.liquid`)
renderizado com o config da unidade. Se preencher o arquivo, a
migration vai passar a usá-lo.
