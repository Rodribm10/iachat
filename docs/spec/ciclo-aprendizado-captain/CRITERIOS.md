# CRITÉRIOS DE ACEITAÇÃO — Ciclo de Aprendizado Autônomo (Fase 1)

Cada item é passa/não-passa. Nada é "pronto" antes de TODOS baterem.

## Dados e estados

- [ ] Migration aplicada: enum com `pending: 0, approved: 1, trial: 2, retired: 3`; colunas `trial_until`, `source`, `judge_verdict`, `retired_at`, `retired_reason` existem.
- [ ] Registros existentes intocados: contagem de `approved` e `pending` antes/depois da migration é idêntica.
- [ ] Default do banco continua `approved` E todos os caminhos automatizados setam status explícito (verificável por grep: nenhum `responses.create!` sem `status:` em jobs/services).
- [ ] `retired` nunca aparece em nenhuma busca; registro aposentado não é deletado.

## Juiz

- [ ] `FaqJudgeService` retorna veredito estruturado (JSON com os 6 critérios + reasoning + modelo) e grava em `judge_verdict` — coberto por spec com fixture.
- [ ] FAQ aprovada pelo juiz fica `trial` com `trial_until ≈ 30 dias`; reprovada fica `pending` com reasoning gravado — specs para ambos.
- [ ] Juiz reprova os casos-armadilha da suite: resposta com preço negociado pontual, resposta com PII, resposta que contradiz FAQ existente da mesma assistant (spec com 3 fixtures mínimas).
- [ ] Falha de API do juiz NÃO perde a FAQ: candidata permanece `pending` e o erro é logado (spec).
- [x] Rake task de calibração roda contra set rotulado e imprime concordância; concordância ≥ 70% no set do Rodrigo ANTES de ligar a flag em produção. **Atingido em 2026-07-26: 23/24 = 95,8%** (24/24 efetivo — a única divergência foi falta de vizinho no harness, já corrigida). Gabarito aprovado pelo Rodrigo.

## Pipeline

- [ ] Conversa com handoff + resposta humana + resolvida → FAQ nasce, passa pelo juiz e entra em `trial` (spec de integração fim-a-fim).
- [ ] Conversa auto-resolvida por inatividade SEM mensagem humana pós-handoff NÃO gera FAQ (spec).
- [ ] `triage_reason` da nota de triagem aparece no metadata da FAQ gerada quando existe (spec).
- [ ] Handoff do motor Captain interno (não-Hermes) grava nota privada com `triage_reason` (spec).
- [ ] Com `feature_faq_auto_judge` desligada, comportamento atual preservado: FAQ nasce `pending` e nada mais acontece (spec).

## Retrieval

- [ ] Os 4 caminhos de busca retornam `approved` E `trial`; NÃO retornam `pending` nem `retired` — 1 spec por caminho (faq_lookup V2, search_documentation, MCP/Hermes, guardrail).
- [ ] Fluxo de FAQ de documento (`Documents::ResponseBuilderJob`) inalterado: regeneração continua funcionando e FAQs de documento nascem `approved` com `source: 'document'` (spec).

## Jobs

- [ ] Job de promoção: `trial` com `trial_until` vencido → `approved`; `trial` dentro do prazo não é tocado; entrada em `config/schedule.yml` (spec + schedule).
- [ ] Digest semanal gera resumo com contagens corretas por unidade (aprendidas, em trial, promovidas, reprovadas pendentes) — spec com dados de fixture.

## Qualidade geral

- [ ] `bundle exec rubocop` verde nos arquivos tocados.
- [ ] `bundle exec rspec` verde na suite completa de enterprise (sem regressão).
- [ ] Strings visíveis ao usuário (digest/UI) com tradução `en` E `pt_BR`.
- [ ] Piloto: flag ligada APENAS na assistant Bianca · H (PrimeAL) no deploy inicial; demais unidades off.
