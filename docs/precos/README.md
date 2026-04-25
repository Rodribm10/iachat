# Tabelas de Preços — Grupo 1001 Noites

Tabelas de preços oficiais **organizadas por MARCA** (não por unidade). Esta pasta é a **fonte de verdade humana** pra consulta rápida sem precisar abrir o Captain ou o app.

> **Por que por marca?** Per padrão `feedback_prompt_scope_by_brand`: preços são iguais entre unidades da mesma marca. O que pode variar entre unidades é a **disponibilidade de categorias** (ex: Pole Dance só em algumas 1001 Noites tradicionais; Hidromassagem só em algumas marcas).

> **Importante:** mudança de preço aqui **não** propaga automaticamente pro Captain. Pra atualizar a Jasmine, é preciso editar os prompts em `db/seed_prompts/_modelos/scenarios/jasmine_*__daniela_reservas.md` — e o sync pro DB de prod acontece automático no próximo deploy via `captain:sync_prompts` no boot do `iachat_iachat_app`.

## Estrutura

```
docs/precos/
├── prime/
│   └── precos_marca_prime.md          # PrimeAL, PrimeVL, Prime ADE (futuro) — Pernoite Especial Prime exclusivo
├── 1001_noites/
│   └── precos_marca_1001_noites.md    # Qnn01 (cadastrada) + Padova/Recanto/Samambaia ADE (pendentes)
├── express/
│   └── precos_marca_express.md        # Express AL — sem Hidromassagem/Stilo/Alexa/Pole Dance/Luxo
└── dolce_amore/
    └── (a preencher quando Dolce Amore for cadastrada — motel-first em Natal/RN)
```

## Última atualização por arquivo

| Arquivo | Última edição | Fonte |
|---|---|---|
| prime/precos_marca_prime.md | 2026-04-25 | Tabela impressa + confirmação Daniela via WhatsApp |
| 1001_noites/precos_marca_1001_noites.md | 2026-04-25 | Tabela enviada pelo Rodrigo + correção qui-dom uniforme via WhatsApp |
| express/precos_marca_express.md | 2026-04-25 | Tabela enviada pelo Rodrigo (5 categorias) |

## Convenções

- Preços sempre em R$ (Reais)
- "Pernoite c/ café" = padrão. "Pernoite SEM café" = R$ 10 a menos
- "Diária" = check-in 12h, duração 24h, café incluso
- "Pernoite" = entrada a partir das 19h, saída até 12h (padrão Prime; outras marcas podem variar)

## Cópia espelhada no Obsidian

Mesma informação salva em `~/Documents/Obsidian Vault/Grupo 1001 Innova/Tabelas de Preço/` (1 arquivo por marca + linkado nos arquivos de marca existentes em `Grupo 1001 Innova/`).
