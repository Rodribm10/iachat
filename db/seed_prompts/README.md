# Captain — prompts versionados

Todo prompt da Jasmine (orchestrator) e dos cenários (Daniela, Maria,
Disponibilidade, etc) vive em arquivos `.md` aqui. O DB é só espelho.

## Estrutura

```
db/seed_prompts/
├── README.md                  ← você está aqui
│
├── _producao_atual/           ← prompts rodando em produção HOJE (com defeitos)
│   │                            extraído de iachat_production em 2026-04-22
│   ├── assistants/  (4 Jasmines: qnn01, primeal, primevl, express)
│   └── scenarios/   (12 cenários, 3 por assistente)
│
├── _modelos/                  ← versões REVISADAS que vão virar a nova produção
│   │                            (o que Rodrigo e Claude testaram no staging,
│   │                             SEMPRE prefixado por unidade: jasmine_<slug>__)
│   ├── assistants/  (ex: jasmine_primeal.md — só PrimeAL validado até agora)
│   └── scenarios/   (ex: jasmine_primeal__daniela_reservas.md)
│
└── target/                    ← APLICADO no DB pela migration de seed
    ├── assistants/
    └── scenarios/
```

## Regra simples

- **`_producao_atual/`** = só referência do que tá em prod hoje. Não é aplicado.
- **`_modelos/`** = só referência dos modelos revisados. Não é aplicado.
- **`target/`** = source of truth. **A migration sincroniza isso no DB**.

Arquivos vazios em `target/` = a migration **não toca** aquele prompt.
Útil pra deployar mudanças seletivas (ex: subir só Daniela melhorada
sem mexer na Jasmine de cada unidade).

## Workflow de revisão (o que estamos fazendo agora)

Pra cada prompt:

1. Olhar `_producao_atual/X.md` (o que tá em prod hoje)
2. Olhar `_modelos/X.md` (se existir — versão revisada)
3. Decidir o conteúdo final: pode ser igual ao modelo, igual ao prod
   ou novo. Salvar em `target/X.md`.
4. Quando todos os prompts revisados estiverem em `target/`, mergear
   pra main e deployar — a migration aplica em prod.

## Convenção de nomes

Os nomes batem com `name`/`title` no banco:

| Slug do arquivo | Captain::Assistant#name |
|---|---|
| `jasmine_qnn01`        | `Jasmine( Qnn01)`     |
| `jasmine_primeal`      | `Jasmine(PrimeAL)`    |
| `jasmine_primevl`      | `Jasmine(PrimeVL)`    |
| `jasmine_express`      | `Jasmine (Express)`   |
| `jasmine_dolce_amore`  | `Jasmine(DolceAmore)` |

| Slug do cenário         | Captain::Scenario#title     |
|---|---|
| `daniela_reservas`        | `Daniela_Reservas`          |
| `disponibilidade_suites`  | `Disponibilidade de suites` |
| `maria_fotos`             | `maria_fotos`               |
| `outras_unidades`         | `outras_unidades`           |
| `reclamacoes_ouvidoria`   | `Reclamacoes_Ouvidoria`     |

## Convenção em `_modelos/` — SEMPRE prefixado por unidade

Cada arquivo em `_modelos/` representa UMA unidade específica, nunca genérico:

- `_modelos/assistants/jasmine_primeal.md` → Jasmine do PrimeAL
- `_modelos/assistants/jasmine_qnn01.md` → Jasmine do Qnn01 (quando criado)
- `_modelos/scenarios/jasmine_primeal__daniela_reservas.md` → Daniela do PrimeAL
- `_modelos/scenarios/jasmine_qnn01__daniela_reservas.md` → Daniela do Qnn01

A migration aplica qualquer arquivo sem prefixo em `target/scenarios/` como
genérico (todas as unidades); com prefixo `<assistant_slug>__` aplica só
naquela unidade, sobrescrevendo o genérico se os dois existirem.

## Estado atual da revisão

Em revisão. `target/` está vazio. Nada será aplicado em prod até
preenchermos os arquivos lá.

**Unidades com modelo validado:**
- [x] PrimeAL (testado em staging 2026-04-23)
- [ ] Qnn01
- [ ] PrimeVL
- [ ] Express
- [ ] Dolce Amore (criado 2026-04-27 — primeira unidade fora do 1001 Noites; marca distinta, motel-first em Natal/RN; não testado em staging ainda)
