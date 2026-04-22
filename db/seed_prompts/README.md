# Captain — prompts versionados

Todo prompt da Jasmine (orchestrator) e dos cenários (Daniela, Maria,
Disponibilidade, etc) vive em arquivos `.md` aqui. O DB é só espelho.

## Estrutura

```
db/seed_prompts/
├── README.md                  ← você está aqui
│
├── _prod_snapshot/            ← snapshot dos prompts ATUAIS de produção
│   │                            (extraído de iachat_production em 2026-04-22)
│   ├── assistants/  (4 Jasmines: qnn01, primeal, primevl, express)
│   └── scenarios/   (12 cenários, 3 por assistente)
│
├── _staging_current/          ← prompts ATIVOS no staging (iachat-v2)
│   │                            que o Rodrigo e Claude revisaram juntos
│   ├── assistants/  (jasmine.md — versão melhorada com saudação nominal)
│   └── scenarios/   (daniela_reservas v3 com pré-reserva, etc)
│
└── target/                    ← APLICADO no DB pela migration de seed
    ├── assistants/
    └── scenarios/
```

## Regra simples

- **`_prod_snapshot/`** = só referência histórica. Não é aplicado.
- **`_staging_current/`** = só referência do que testamos. Não é aplicado.
- **`target/`** = source of truth. **A migration sincroniza isso no DB**.

Arquivos vazios em `target/` = a migration **não toca** aquele prompt.
Útil pra deployar mudanças seletivas (ex: subir só Daniela melhorada
sem mexer na Jasmine de cada unidade).

## Workflow de revisão (o que estamos fazendo agora)

Pra cada prompt:

1. Olhar `_prod_snapshot/X.md` (o que tá em prod hoje)
2. Olhar `_staging_current/X.md` (se existir — versão melhorada)
3. Decidir o conteúdo final: pode ser igual ao staging, igual ao prod
   ou novo. Salvar em `target/X.md`.
4. Quando todos os prompts revisados estiverem em `target/`, mergear
   pra main e deployar — a migration aplica em prod.

## Convenção de nomes

Os nomes batem com `name`/`title` no banco:

| Slug do arquivo | Captain::Assistant#name |
|---|---|
| `jasmine_qnn01`   | `Jasmine( Qnn01)`   |
| `jasmine_primeal` | `Jasmine(PrimeAL)`  |
| `jasmine_primevl` | `Jasmine(PrimeVL)`  |
| `jasmine_express` | `Jasmine (Express)` |

| Slug do cenário         | Captain::Scenario#title     |
|---|---|
| `daniela_reservas`        | `Daniela_Reservas`          |
| `disponibilidade_suites`  | `Disponibilidade de suites` |
| `maria_fotos`             | `maria_fotos`               |
| `outras_unidades`         | `outras_unidades`           |
| `reclamacoes_ouvidoria`   | `Reclamacoes_Ouvidoria`     |

Cenários se aplicam a TODAS as unidades cujo arquivo bate. Pra
customizar por unidade, prefixe com `<assistant_slug>__`:

- `target/scenarios/daniela_reservas.md` → aplica em todas as 4
- `target/scenarios/jasmine_primeal__daniela_reservas.md` → só PrimeAL
  (sobrescreve o genérico se ambos existirem)

## Estado atual da revisão

Em revisão. `target/` está vazio. Nada será aplicado em prod até
preenchermos os arquivos lá.
