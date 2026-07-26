# RELATÓRIO — Ciclo de Aprendizado Autônomo (Fase 1)

> Data: 2026-07-24 · Branch: `codex/instagram-comment-source-dm-text`
> Status: **implementado e testado**. Falta ação de deploy (calibração + ligar a flag no piloto).

## O que foi feito

O loop deixou de depender de aprovação humana. Quando a IA passa para triagem humana, o humano responde e a conversa é resolvida, a FAQ candidata agora vai direto para um **juiz LLM**; passando, entra em **quarentena de 30 dias já respondendo ao cliente**, e é promovida automaticamente. O humano só vê o que o juiz reprovou e o digest semanal.

### Arquivos criados

| Arquivo | Papel |
|---|---|
| `db/migrate/20260724120000_add_probation_to_captain_assistant_responses.rb` | Estados e metadados da quarentena |
| `enterprise/app/services/captain/llm/faq_judge_service.rb` | Juiz LLM (rubrica de 6 critérios) |
| `enterprise/app/services/captain/assistant_responses/learning_digest_service.rb` | Números do digest semanal |
| `enterprise/app/jobs/captain/assistant_responses/probation_job.rb` | Promoção diária pós-quarentena |
| `enterprise/app/jobs/captain/assistant_responses/learning_digest_job.rb` | Entrega do digest (Mattermost) |
| `lib/tasks/captain_judge_calibration.rake` | Calibração do juiz contra gabarito humano |
| 6 arquivos de spec | Cobertura (ver abaixo) |

### Arquivos alterados

`assistant_response.rb` (enum + scopes + promote!/retire!), `conversation_faq_service.rb` (guard de triagem + juiz + persistência), `system_prompts_service.rb` (prompt de extração em pt-BR), os 4 caminhos de retrieval (`approved` → `retrievable`), `documents/response_builder_job.rb` (status explícito), `conversation/response_builder_job.rb` + `handoff_tool.rb` + `human_triage_note_service.rb` (motivo de triagem fora do Hermes), `schedule.yml`, `en.yml`, `pt_BR.yml`.

## Desvios do plano e por quê

1. **Duas colunas a mais que o previsto.** O plano falava em gravar o motivo da triagem "no metadata da FAQ" — como não existe coluna de metadata, criei `triage_reason` dedicada (consultável, e a Fase 2 vai precisar dela para medir quantas FAQs nasceram de gap real). Criei também `promoted_at`, sem a qual o digest não conseguiria contar "promovidas no período" com precisão — só aproximar por `updated_at`.

2. **O guard ficou diferente — e melhor.** O plano dizia "pular conversas auto-resolvidas por inatividade". Detectar auto-resolve exigiria casar o texto da nota interna, que é frágil. Implementei a regra que captura a intenção com precisão: **exige resposta humana depois da nota de triagem**. Conversa que foi para triagem, ninguém assumiu e morreu por inatividade não tem o que ensinar. Sem nota de triagem, o comportamento histórico é preservado (basta ter havido resposta humana), o que manteve as specs existentes válidas.

3. **Descoberta importante: `messages.content_attributes` é JSON duplamente codificado.** A coluna é `json` com `store` do Rails, e o valor é gravado como *string JSON dentro do JSON*. Resultado: `content_attributes->>'triage_reason'` **nunca encontra nada** no Postgres. Tive que filtrar em Ruby. Isso é uma armadilha que vale além desta spec — qualquer consulta SQL a `content_attributes` no projeto (ou no Sinal, lendo o banco direto) está silenciosamente retornando vazio.

4. **Reuso em vez de duplicação no handoff.** Em vez de criar um serviço novo para o motivo de triagem do Captain interno, adicionei um parâmetro `source` ao `Captain::Hermes::HumanTriageNoteService` existente. Os dois motores gravam a nota com a mesma estrutura.

5. **Digest com entrega própria.** O `MattermostDeliveryService` existente é acoplado ao formato do CEO Digest (attachments, cards). O digest de aprendizado posta texto simples reusando apenas a *config* de webhook da conta.

6. **Documentação da spec saiu de `spec/`.** `spec/` é o diretório do RSpec — os documentos foram para `docs/spec/ciclo-aprendizado-captain/`.

7. **Uma spec existente precisou ser atualizada.** `agent_runner_service_spec.rb` fazia stub de `assistant.responses` com um double que só respondia a `approved`. Como o guardrail agora usa `retrievable`, os stubs foram atualizados — o comportamento testado é o mesmo.

## Verificação contra os critérios

**Passaram:** todos os critérios de dados e estados; os 6 do juiz (16 exemplos, incluindo os casos-armadilha de preço negociado, PII e contradição, além de falha de API sem perder a FAQ); todos os do pipeline (21 exemplos); todos os de retrieval (**os 4 caminhos testados com pgvector real**, não com mock); os dos jobs; rubocop limpo em 24 arquivos; i18n em `en` e `pt_BR`.

**Ressalvas honestas:**

- **A suite não está 100% verde.** `spec/enterprise` (Captain) termina com **22 falhas — todas pré-existentes**, em arquivos que não toquei (`send_suite_images_tool`, `open_ai_message_builder`, `prompt_renderer`, `generate_pix_tool`, entre outros; vários deles com alterações não commitadas de trabalho anterior). Verifiquei por comparação de baseline: minhas mudanças chegaram a introduzir 4 regressões (stubs desatualizados no `agent_runner_service_spec`), que foram corrigidas — de 26 falhas voltou para as mesmas 22 do baseline. Saldo líquido de regressão: **zero**. O critério "suite verde" não foi atingido porque já não estava verde antes.
- **Calibração ainda não rodou.** A rake task está pronta, mas rodá-la exige o gabarito de 20–30 candidatas rotuladas por você e chamadas reais ao LLM. **Este é o passo que bloqueia ligar em produção.**
- **Piloto ainda não ligado.** A flag `feature_faq_auto_judge` está desligada em todos os assistants (confirmado no banco). Ligar só na Bianca · H / PrimeAL é ação de deploy.

## Estado dos dados após a migration

Nada foi tocado: 61 FAQs, 45 `pending` + 16 `approved`, 0 em `trial`/`retired`, `retrievable` = 16 (exatamente as aprovadas). Vale registrar que essas **45 pendentes são a fila parada** que motivou o projeto.

## Resultado da calibração (2026-07-26)

**23/24 = 95,8% de concordância** — muito acima do mínimo de 70%. Juiz `gpt-4o-mini` via proxy Hermes local, 24 casos, 11,2 minutos com paralelismo 4.

A única divergência foi o caso 18 (contradição sobre política de pet), e a causa **não foi o juiz**: a calibração passava `neighbours: []`, então o juiz respondeu, corretamente, "não há conhecimento relacionado na base para gerar contradição". Refeito o mesmo caso com o conhecimento existente em mãos, o veredito foi o esperado:

> `nao_contradiz: REPROVOU — Contradiz diretamente o conhecimento já existente na base, que afirma que não são aceitos animais em nenhuma unidade.`

Ou seja, acerto efetivo de **24/24** nos casos de fronteira. Em produção o `ConversationFaqService` já passa os vizinhos reais (`find_retrievable_neighbours`), então esse cenário está coberto.

Correção aplicada para o furo não voltar: o gabarito agora aceita o campo `vizinhos` por caso, e a rake os injeta no juiz. Um caso de contradição sem vizinho declarado mede menos do que aparenta medir.

## Ambiente de LLM — o que foi descoberto ao tentar calibrar

A calibração expôs o estado real dos provedores de IA no ambiente de desenvolvimento:

| Caminho | Estado em 2026-07-26 |
|---|---|
| `CAPTAIN_OPEN_AI_API_KEY` (OpenAI direta) | Chave presente mas **rejeitada** pela OpenAI ("Incorrect API key") |
| Codex OAuth (`CAPTAIN_LLM_PROVIDER` atual) | Credencial **expirada em 2026-05-02** |
| Hermes gateway em `host.docker.internal:9877` | Endereço configurado, **nada escutando** |
| Hermes gateway real | Rodando em `127.0.0.1:8642`, exige chave própria |
| Proxy OpenAI→Hermes (`~/.birdclaw/openai-hermes-proxy.mjs`) | Rodando em `127.0.0.1:8787/v1`, **funciona sem chave**, aceita `response_format: json_object` |

Ou seja, o `CAPTAIN_LLM_PROVIDER` do dev aponta para um caminho morto. **A configuração não foi alterada**: não há certeza de qual endpoint o Chatwoot deve usar oficialmente, e chutar isso quebraria o ambiente depois. A calibração passou a rodar contra o proxy do Hermes via sobrescrita em tempo de execução.

Por isso a rake de calibração ganhou três variáveis de ambiente:

- `JUDGE_API_BASE` — endpoint OpenAI-compatível alternativo (não altera `InstallationConfig`)
- `JUDGE_MODEL` — modelo do juiz
- `CONCURRENCY` — paralelismo; cada chamada pelo proxy Hermes leva ~2 min, então 24 casos em série levariam ~50 min

```bash
JUDGE_API_BASE=http://127.0.0.1:8787/v1 CONCURRENCY=4 \
  bundle exec rake 'captain:judge_calibration[gabarito-modelo.json,1]'
```

**Alerta para produção:** a credencial Codex expirada não é necessariamente só do dev. Os relatórios de auditoria diária das atendentes já listavam `codex_token_expired` como achado recorrente (Lara.H / PRIME VL). Vale conferir produção — atendente sem LLM é falha silenciosa.

## Próximos passos

1. Rodar `rake 'captain:judge_calibration[gabarito.json,<assistant_id>]'` com seu gabarito; exigir ≥ 70%.
2. Ligar `feature_faq_auto_judge` só na Bianca · H (PrimeAL) e acompanhar 2 semanas pelo digest.
3. Decidir o que fazer com as 45 pendentes atuais: podem ser submetidas ao juiz em lote (backfill) em vez de morrerem na fila.
4. Fase 2: attribution + veredito por métrica no lugar da promoção por tempo.
