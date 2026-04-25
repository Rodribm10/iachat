# Tabelas de Preços — Grupo 1001 Noites

Tabelas de preços oficiais das unidades, separadas por marca. Esta pasta é a **fonte de verdade humana** pra consulta rápida sem precisar abrir o Captain ou o app.

> **Importante:** mudança de preço aqui **não** propaga automaticamente pro Captain. Pra atualizar a Jasmine, é preciso editar os prompts em `db/seed_prompts/_modelos/scenarios/jasmine_*__daniela_reservas.md` e sincronizar com o DB de prod.

## Estrutura

```
docs/precos/
├── prime/                 # Pernoite Especial Prime exclusivo da marca
│   └── precos_marca_prime.md   # vale pra PrimeAL e PrimeVL (preços iguais)
├── 1001_noites/           # Marca tradicional, com Pole Dance em algumas unidades
│   └── precos_qnn01.md
├── express/               # Sem Hidromassagem/Stilo/Alexa
│   └── precos_express_al.md
└── dolce_amore/           # Motel-first em Natal/RN
    └── (a preencher)
```

## Última atualização por arquivo

| Arquivo | Última edição | Fonte |
|---|---|---|
| prime/precos_marca_prime.md | 2026-04-25 | Tabela impressa + confirmação Daniela via WhatsApp |
| 1001_noites/precos_qnn01.md | 2026-04-25 | Tabela enviada pelo Rodrigo (com pendências) |
| express/precos_express_al.md | 2026-04-25 | Tabela enviada pelo Rodrigo |

## Convenções

- Preços sempre em R$ (Reais)
- "Pernoite c/ café" = padrão. "Pernoite SEM café" = R$ 10 a menos
- "Diária" = check-in 12h, duração 24h, café incluso
- "Pernoite" = entrada a partir das 19h, saída até 12h
