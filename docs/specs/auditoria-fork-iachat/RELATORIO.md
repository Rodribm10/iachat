# RELATÓRIO

## F0 — Triagem em produção — 22/08/2026

Fonte: `iachat_production` na VPS `76.13.174.155`, container `iachat_iachat_postgres`.
Somente `SELECT`. Nenhuma escrita.

### Contas

| id | conta | criada | inboxes | conversas |
|---:|---|---|---:|---:|
| 1 | Grupo1001 | 25/02/2026 | 17 | 23.686 |
| 2 | **Zelo Health Club** | 22/08/2026 | 1 | 2 |

A conta 2 é a academia. Inbox 25 — "Academia Dom Bosco — GoWA", `Channel::Whatsapp` via GOWA.
**Ainda sem `captain_unit` e sem assistant atrelado.**

### Motor de resposta — o portão do F3 está aberto

```
captain_assistants por engine:   hermes 13  |  captain_interno 5
inboxes com assistant:           12         |  0
```

Os 5 em `captain_interno` (Juliana, Bianca, Lara, Nina, Valentina) têm **zero inboxes** — são as
versões antigas, já substituídas pelas gêmeas `· H`. **Nenhuma inbox de produção roteia para o
motor interno.** O portão de entrada do F3 (desligar o Captain interno) está satisfeito.

As 12 inboxes atendidas, todas em Hermes: PRIME AL, PRIME VL, EXPRESS, PRIMEADE, PADOVA,
Recanto Das Emas, Motel Samambaia, Qnn01, hoteis1001noites (IG), hoteis1001prime (IG),
Hotéis 1001 Noites (Site), Anúncio 1001 Noites.

### Volumes por subsistema (90 dias, salvo indicado)

| Subsistema | Número | Destino |
|---|---:|---|
| Reservas | 149 | **VIVO** |
| Cobranças PIX | 126 | **VIVO** |
| Insights de conversa (total) | 1.767 | **VIVO** |
| Unidades | 11 | **VIVO** |
| Itens de galeria | 20 | **VIVO** |
| Landing hosts / cliques | 2 hosts, 15 cliques | **VIVO, mas raso** |
| Regras de lifecycle | **0** | nunca usado |
| Entregas de lifecycle | **0** | nunca usado |
| Memórias de contato | **0** | 4 crons rodando pra nada |
| Snapshots de relatório | **0** | confirmado morto |

### Providers de WhatsApp

```
wuzapi  10 canais, 10 com inbox
gowa     1 canal,   1 com inbox   (a academia)
```

`baileys`, `zapi`, `evolution`, `whatsapp_cloud`, `default` (360dialog): **zero canais**.
Cinco providers de código sem nenhum uso.

### As 20 tabelas órfãs — todas vazias

`captain_prompt_blocks`, `captain_prompt_versions`, `captain_prompt_block_versions`,
`captain_prompt_profiles`, `captain_prompt_audit_events`, `captain_prompt_improvement_cases`,
`captain_suites`, `captain_assets`, `captain_extras`, `captain_configurations`,
`conversation_crm_insights`, `frequent_questions`, `whatsapp_campaigns`,
`whatsapp_campaign_hits`, `jasmine_documents`, `jasmine_document_chunks`,
`jasmine_collections`, `jasmine_inbox_settings`, `jasmine_tool_configs`,
`jasmine_inbox_collections` — **0 linhas em todas**.

Não há nada a exportar antes do `drop_table`.

### Onde meu palpite prévio errou

| Palpite da auditoria | Realidade | Veredito |
|---|---|---|
| Lifecycle: "parado mas útil, provavelmente já rodou" | 0 regras, 0 entregas — **nunca rodou uma vez** | errei o "já rodou"; o "útil" continua em aberto |
| Memórias de contato: "confirmar se entra no prompt" | 0 registros — não entra em lugar nenhum | 4 crons queimando ciclo à toa |
| Captain interno: "pergunta que decide metade da faxina" | 5 assistants órfãos, 0 inboxes | podia ter sido respondido em uma consulta |
| Tabelas órfãs: "checar se tem linha antes do drop" | todas vazias | cautela desnecessária, mas correta |

### O que esta consulta **não** responde

A roleta não tem tabela neste banco — nem `roleta`, nem `draw`, nem coluna equivalente em
`captain_reservations`. O estado dela vive no **Supabase** (schema `reserva_hotel`, conforme
`Captain::Roleta::OfferService::DEFAULT_SCHEMA`). Medir uso da roleta exige consultar o Supabase
ou resposta direta do Rodrigo.
