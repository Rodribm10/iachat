# Captain — Indicadores de Retenção e Recorrência

Design e implementação do sistema de métricas de retenção para motel (negociado
com Rodrigo em 2026-04-22).

## Regras de negócio

### Definição de "interação"
- Todas as mensagens públicas (não-privadas, status != failed) do contato e do
  atendimento (Captain::Assistant ou User) são consideradas.
- **Gap de 30h** entre a última msg de uma interação e a próxima msg abre uma
  nova interação. Abaixo disso, mesma "sessão".
- Motivo: motel tem frequência alta (múltiplas visitas na mesma semana); 30h
  evita que manhã+tarde virem 2 interações mas captura corretamente
  "voltou-no-dia-seguinte".

### Classificação de cada grupo
| Cliente | Atendimento | Tipo |
|---------|-------------|------|
| ≥ 2 msgs textuais | ≥ 2 msgs textuais | **qualificada** (conta em `interactions_count`) |
| ≥ 1 msg textual | ≥ 1 msg textual | **one-shot** (conta em `one_shot_consultations_count`) |
| 0 de um dos lados | — | ignorado |

**Textual** = pelo menos 2 letras (`\p{L}`). Exclui emoji-only, sticker,
"Message without content".

### Exclusão
Contatos com o label `equipe_interna` (manual) são ignorados em todas as
métricas. Aplica-se a gerentes, testes, números internos.

### Recorrência
`is_recurring = interactions_count >= 2`.

### Reservas vs Pix
- `pix_generated_count`: toda `Captain::PixCharge` criada (sinal de intenção).
- `reservations_paid_count`: `Captain::PixCharge.where(status: 'paid')` (reserva real).
- Conversão = paid / generated.

## Colunas em `contacts`

| Coluna | Tipo | Atualizada por |
|--------|------|----------------|
| `interactions_count` | integer | `Captain::Retention::RecalculateContactStatsJob` |
| `one_shot_consultations_count` | integer | idem |
| `first_interaction_at` | datetime | idem |
| `last_interaction_at` | datetime | idem |
| `pix_generated_count` | integer | idem (conta PixCharges) |
| `reservations_paid_count` | integer | idem |
| `is_recurring` | boolean | idem |
| `days_since_last_interaction` | integer | idem (recalculado no job) |

## Fluxo de atualização

- **Job diário** (`captain_retention_recalculate_all_contact_stats_job`, 6h UTC
  / 3h BRT): itera todos os contatos com conversa nos últimos 120 dias e
  enfileira `RecalculateContactStatsJob` por contact.
- **Evento conversa resolvida**: `CaptainListener#conversation_resolved`
  enfileira recalc incremental do contato.
- **Evento PixCharge**: `after_create_commit` e `after_update_commit`
  enfileiram recalc (cobre geração e mudança pra paid/expired/failed).

## Endpoints

### `GET /api/v1/accounts/:id/captain/reports/retention`
Params: `start_date`, `end_date` (ISO, opcional, default = mês corrente).

Resposta:
```json
{
  "period": { "start": "2026-04-01", "end": "2026-04-22" },
  "status": {
    "active": 340, "recurring": 85, "sleeping": 62,
    "at_risk": 30, "churned": 15, "never_interacted": 0
  },
  "flow": { "new": 120, "returned": 40, "total_touches": 160 },
  "pix": { "generated": 180, "paid": 45, "conversion_rate": 0.25 },
  "retention": { "last_30d": 0.28, "last_90d": 0.12 }
}
```

Cortes de status (relativos a `Time.current`):
- **active**: `last_interaction_at >= now - 30d`
- **recurring**: `is_recurring=true AND last_interaction_at >= now - 90d`
- **sleeping**: `last_interaction_at` entre 30 e 90 dias atrás
- **at_risk**: entre 90 e 180 dias atrás
- **churned**: mais de 180 dias atrás
- **never_interacted**: `last_interaction_at IS NULL`

### `GET /api/v1/accounts/:id/captain/reports/retention/cohort`
Params: `history_months` (default 12, max 24).

Resposta: matriz com `cohorts` (linha por mês), cada linha tem
`size` + `retention[]` (array de 13 objetos: offset 0..12 com count e rate).

Cohort = mês da `first_interaction_at`. Célula [cohort, M+N] = % de contatos
da cohort com qualquer msg de cliente no mês M+N.

## UI

- **Aba Retenção em Relatórios do Captain** (`retention/RetentionTab.vue`):
  - KpiCards: 4 cards (ativos, recorrentes, retorno 30d, conversão Pix)
  - FlowCard: novos vs retornaram no período + situação absoluta (sleeping/
    at_risk/churned)
  - CohortMatrix: tabela cohort 12x13 com heatmap verde + export CSV
- **Badge no card de contato** (`RetentionSummaryBadge.vue`): mostra tier
  (Primeiro contato/Ativo/Recorrente/Adormecido/Em risco/Inativo) + contadores
  + "última há X dias".
- **Filtros na lista de contatos** (`contactProvider.js`): 5 filtros novos —
  cliente recorrente, última interação, dias sem interagir, nº de interações,
  reservas pagas.

## Queries SQL de backup

Contagem rápida de ativos no mês:
```sql
SELECT COUNT(*) FROM contacts
WHERE account_id = $1 AND last_interaction_at >= NOW() - INTERVAL '30 days';
```

Taxa de retorno 30d da cohort de 30-37 dias atrás:
```sql
WITH cohort AS (
  SELECT id FROM contacts
  WHERE account_id = $1
    AND first_interaction_at BETWEEN NOW() - INTERVAL '37 days' AND NOW() - INTERVAL '30 days'
)
SELECT (COUNT(*) FILTER (WHERE c.last_interaction_at >= NOW() - INTERVAL '7 days'))::float
     / NULLIF(COUNT(*), 0) AS rate
FROM contacts c WHERE c.id IN (SELECT id FROM cohort);
```

## Próximos passos possíveis

- Recalcular `first_interaction_at` / `last_interaction_at` via SQL direto
  no job (atualmente é via service Ruby — OK até ~10k contatos ativos).
- Widget "Top recorrentes" (ranking dos contatos com mais reservas pagas).
- Alerta quando taxa de retorno cai > 10% mês a mês.
- Histórico da métrica para rodar tendências (tabela `retention_snapshots`).
