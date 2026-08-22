# Catálogo dos relatórios do Sinal — o que trazer pro Chatwoot

Levantado em 22/08/2026 a partir de `sinal-whatsapp/artifacts/api-server/src/routes/metrics.ts`
(2.331 linhas, 15 endpoints) e das telas `overview.tsx` e `ia-auditoria.tsx`.

**Decisão do Rodrigo:** construir isto **depois do sync 4.11 → 4.17**, para não criar arquivos
novos em `routes/dashboard/settings/reports/` — uma das áreas que o upstream mais mexe. Entrega
**fatiada**: primeiro a cobertura da IA, depois o resto.

> Diferença de fundo: o Sinal calcula tudo a partir de um **espelho** (`whatsapp_messages`, com
> `metadata->>'conversation_id'` e `inbox_id` apontando de volta pro Chatwoot). Aqui o dado é a
> fonte. Toda métrica portada fica **mais simples e mais exata** do que no original — não se deve
> traduzir o SQL do Sinal, e sim reescrever contra `conversations` / `messages`.

## Grupo 1 — porta direto

| Relatório do Sinal | Endpoint | Fonte no Chatwoot |
|---|---|---|
| Cobertura da IA por caixa de entrada | `/metrics/private/ai-coverage` | `messages.sender_type` = `Captain::Assistant` vs `User` |
| Formato do atendimento (só IA / misto / só humano) | idem | idem, agregado por conversa |
| Volume diário recebidas × enviadas | `/metrics/private/volume` | `messages.message_type` |
| Handoff IA → humano | `/metrics/private/ai-flow` | etiquetas `triagem_humana`, `triagem_*` |
| Fila sem resposta | `/metrics/private/unanswered`, `/pending` | última msg da conversa é `incoming` |
| Tempo de resposta em **minutos úteis** | `/metrics/private/operations` | **o Chatwoot nativo não faz** — janela 08–20, seg–sex, TZ São Paulo |
| Operação por agente (conversas, msgs, sessões, minutos online) | `/metrics/private/operations` | parcialmente coberto pelo Relatório de Agentes |
| Fotos pedidas × enviadas | `/metrics/private/ai-flow` | tool `send_suite_images` |
| PIX e reservas geradas pela IA | — | `captain_pix_charges`, `captain_reservations` |
| Áudios e minutos de áudio | `/metrics/overview` | `attachments` |
| Top contatos por volume | `/metrics/private/top-contacts` | `messages` por contato |

## Grupo 2 — precisa de pipeline, não de relatório

Dependem de uma etapa de enriquecimento por LLM que o Sinal roda e o Chatwoot não tem como
agregação pronta. **Matéria-prima existe:** `captain_conversation_insights` já tem 1.767 registros.

- Distribuição por categoria (Comercial / Reclamação / Mídia / Outros) — `/metrics/private/categories`
- Sentimento — `/metrics/private/sentiment`
- Pautas em alta — `/metrics/private/trending`
- Painel de inteligência (pauta × contatos que a geram) — `/metrics/private/intelligence`
- Convites e oportunidades — `/metrics/private/invites`

## Grupo 3 — não se aplica

O Sinal monitora o WhatsApp **pessoal** do Rodrigo; aqui é atendimento de empresa.

- Nuvem de tópicos de grupos — `/metrics/groups/topics`
- Thread de DM privada — `/metrics/private/thread`

## Arquitetura acordada

Duas páginas, sem duplicar o que o Chatwoot já entrega (Agentes, Conversas, CSAT, SLA):

**`/reports/ia`** — cobertura da IA por caixa (topo), formato do atendimento, handoff com motivos
reais, e o que a IA produziu (fotos, PIX, reservas). Junto do CEO Digest, funil e retenção que já
moram lá.

**`/reports/operacao`** — só o que falta no Chatwoot: tempo de resposta em minutos úteis, fila
esperando agora, volume separado IA × humano.

## Prova de viabilidade — rodado em produção em 22/08/2026 (7 dias)

| Caixa | Atendimentos | Com IA | Só IA | Misto | Só humano | % msgs da IA |
|---|---:|---:|---:|---:|---:|---:|
| PRIME AL | 287 | 98,3% | 79,4% | 18,8% | 1,7% | 86,8% |
| Qnn01 | 103 | 100% | 74,8% | 25,2% | 0% | 82,6% |
| **DOLCE AMORE** | 102 | **42,2%** | 27,5% | 14,7% | **57,8%** | **39,8%** |
| PRIME VL | 97 | 100% | 92,8% | 7,2% | 0% | 97,0% |
| Site 1001 | 94 | 100% | 100% | 0% | 0% | 100% |
| EXPRESS | 61 | 100% | 62,3% | 37,7% | 0% | 63,0% |
| PADOVA | 57 | 100% | 93,0% | 7,0% | 0% | 96,0% |
| Motel Samambaia | 52 | 100% | 90,4% | 9,6% | 0% | 93,4% |

**Achado que já vale o relatório:** todas as unidades operam com participação da IA em 100% —
menos o **DOLCE AMORE**, com 42%. Mais da metade dos atendimentos dele nos últimos 7 dias foi
só humano, sem a IA encostar. É a única fora da curva, e hoje não há tela que mostre isso.
Investigar em paralelo, independe do relatório.

## Nota técnica

`messages` tem 1.126 registros em 7 dias com `message_type = 1` e `sender_type` nulo — mensagens
automáticas (templates, auto-resolve, saudação). Precisam sair da conta de "humano" ou virar uma
terceira categoria, senão inflam o denominador.
