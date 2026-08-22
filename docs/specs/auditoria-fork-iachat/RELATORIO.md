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

---

## F1 — Remoção do morto — 22/08/2026

Branch `chore/enxugar-fork`, três commits.

### O que saiu

| Bloco | Detalhe |
|---|---|
| Subsistema Jasmine (RAG) | componentes nunca importados + cliente de API sem rota no backend |
| Classes sem chamador | `Captain::Inter::WebhookSetupService`, `Captain::Notifications::SendNotificationService`, `Captain::ToolRegistryService`, `Captain::Tools::BaseService`, `Whatsapp::MessageDedupLock`, `Whatsapp::Providers::EvolutionApi::PayloadParser` |
| Gravador sem leitor | `Captain::Reports::DailySnapshotJob` + `Captain::ReportSnapshot` |
| Lifecycle / concierge | 74 arquivos: models, services, 6 guards, jobs, controllers, policies, views, store, rotas e telas |
| Memórias de contato | 4 crons, 6 jobs, 4 services, model, policy, controller, tela, injetor de prompt |
| Lixo de repositório | `chatwoot_zero/` (2 PNGs de uma cópia velha), `TestIndex.vue` |
| Banco | migration derrubando **25 tabelas**, todas confirmadas vazias em produção |

**Saldo: 129 arquivos alterados, −6.451 linhas.**

### O que NÃO saiu, e por quê

- **`Reports::ExecutiveController`** — a v1 da auditoria dizia "sem rota". Errado: está em
  `config/routes.rb:120` e alimenta a tela de relatórios.
- **Camada `Captain::Tools::*`** — resolvida dinamicamente por `config/agents/tools.yml`.
  É a camada de tools do motor interno; sai junto com ele no F3.
- **Chaves i18n `JASMINE.CONFIG/WUZAPI/EVOLUTION`** — a tela de configuração do Wuzapi ainda
  usa, e são 10 canais vivos em produção. Removidas só `HEADER`, `KNOWLEDGE_BASE`,
  `PLAYGROUND` e `INBOX_LIST`.
- **Providers de WhatsApp** — decisão do Rodrigo: não mexer antes do sync.

### Achado no meio do caminho

O instalador do AIOS havia **sobrescrito o `.env.example` do Chatwoot inteiro** — de 372 linhas
para 114 —, apagando `SECRET_KEY_BASE`, `REDIS_URL`, `POSTGRES_HOST`, `FRONTEND_URL` e o resto
da configuração real. Quem fosse provisionar uma instância nova a partir desse arquivo não
conseguiria. Restaurado do upstream e acrescido de uma seção com as variáveis próprias do fork;
as credenciais de ferramenta de desenvolvimento foram para `.env.aios.example`.

Também: `Captain::Lifecycle::ContextBuilder` tinha um consumidor fora do subsistema (`Agentable`,
na interpolação de prompt). Virou `Captain::Reservations::ContextBuilder`, com o formato dos
campos preservado tal e qual.

### Verificação

| Check | Resultado |
|---|---|
| `rails zeitwerk:check` | passa |
| `db:migrate` → `db:rollback` → `db:migrate` | sem erro, migration reversível de verdade |
| `rubocop` nos arquivos tocados | limpo |
| `eslint` nos arquivos tocados | limpo |
| RSpec `spec/enterprise` — **base** (`origin/main`) | 1822 exemplos, **87 falhas** |
| RSpec `spec/enterprise` — **esta branch** | 1630 exemplos, **59 falhas** |
| Falhas novas introduzidas | **zero** |

A suíte do fork **já estava vermelha antes** — 87 falhas no `origin/main`, espalhadas por Stripe,
SAML, Twilio, Cloudflare e specs desatualizados em relação ao próprio código do fork (ex.:
`hook_execution_service_spec` espera `perform_later(conversation, assistant)` enquanto o código
passa três argumentos há tempo). Isso é dívida a atacar, mas é anterior a esta limpeza.

Duas falhas foram investigadas e descartadas como ruído de ambiente:
- `account_saml_settings_spec` falha por causa do `FRONTEND_URL` apontando pra um túnel ngrok no
  `.env` local; com `FRONTEND_URL=http://localhost:3000` passa.
- `filterHelpers.spec.js` compara timestamps fixos de 2022 com datas relativas — teste que
  apodrece com o tempo, em arquivo que esta branch não tocou.

### Ordem de deploy (importante)

O código novo não toca em nenhuma das 25 tabelas. Então: **subir o código primeiro, rodar a
migration depois**. Nesse intervalo um rollback de imagem continua funcionando, porque a imagem
antiga ainda encontra as tabelas onde espera.

---

## Desvio do plano — F3 estava errado (22/08/2026)

Pergunta do Rodrigo ("por que desligar o Captain interno? atrapalha alguma coisa?") levou a uma
verificação que **derrubou uma premissa do plano congelado**. Registrando conforme o protocolo:
paro, explico, peço re-aprovação.

### O erro

O F3.2 mandava remover, junto com o motor interno:

```
enterprise/app/services/captain/codex/{auth_service,client,translator}.rb
enterprise/app/jobs/captain/codex/refresh_tokens_job.rb
enterprise/app/models/captain/codex_credential.rb + tabela
cron captain_codex_refresh_tokens_job
```

**Isso teria quebrado produção.** O Codex não é do motor interno — é o *backend de LLM do fork
inteiro*. `Captain::Llm::ProviderConfig` e `lib/llm/config.rb` apontam o cliente OpenAI para o
proxy interno (`/codex/v1/chat/completions`) quando `CAPTAIN_LLM_PROVIDER=openai_codex_oauth`.

Consumidores vivos, todos no caminho do Hermes:

| Consumidor | O que faz |
|---|---|
| `Captain::Llm::ContactNotesService` | transforma conversa resolvida em nota de CRM |
| `Captain::Llm::EmbeddingService` | embeddings de FAQ e documento |
| `Captain::Llm::FaqJudgeService` | juiz do ciclo de aprendizado |
| `Captain::Llm::TranslateQueryService` | tradução de consulta |
| `Captain::Health::ConexoesService` | sensor de saúde |

Evidência em produção: o log do container mostra `POST /codex/v1/chat/completions` várias vezes
por hora, vindo de `10.0.0.2`, com o prompt do note taker. E `captain_codex_credentials` tem a
credencial 3 **ativa**, renovada em 15/08 — o cron de 30 minutos está fazendo o trabalho dele.

### O que de fato está morto

Só o **motor de resposta**: `Captain::Conversation::ResponseBuilderJob`,
`Captain::Assistant::AgentRunnerService`, `Captain::Llm::AssistantChatService`, a camada
`Captain::Tools::*` e o `config/agents/tools.yml`. Zero inboxes roteiam pra lá.

### Risco concreto que motiva a remoção

`captain_assistants.engine` tem **default `captain_interno`** (`db/schema.rb:337`). Um assistant
criado agora nasce apontando pro motor morto. Como a inbox da academia (Zelo Health Club) ainda
não tem assistant atrelado, esse é o próximo passo do Rodrigo — e ele cairia exatamente nessa
armadilha.

### Escopo corrigido, a aprovar

- **Sai:** motor de resposta + `tools.yml` + `Captain::Tools::*` (menos `GeneratePixTool`).
- **Fica:** todo o Codex — proxy, credencial, auth, translator e o cron de 30 minutos.
- **Corrige:** default da coluna `engine` passa a ser `hermes`.

---

## Default `engine` = hermes — tentado e revertido (22/08/2026)

Decisão do Rodrigo: não mexer no motor interno, só trocar o default da coluna
`captain_assistants.engine` para `hermes`. Implementado, testado — e **revertido**, porque
quebra mais do que conserta.

### Por quê

`Captain::Assistant` valida, quando `engine == 'hermes'`:

```ruby
validates :hermes_profile_name, presence: true, if: :hermes?
validates :hermes_webhook_base_url, presence: true, if: :hermes?
```

E o formulário de criação no painel
(`components-next/captain/pageComponents/assistant/AssistantForm.vue`) tem apenas **nome,
descrição, nome do produto e três checkboxes**. Nenhuma referência a `hermes_profile_name` em
todo o `app/javascript`.

Ou seja: com o default em `hermes`, **criar assistant pelo painel passa a falhar** com
"Hermes profile name can't be blank".

Medido na suíte: `spec/enterprise` foi de 59 para **641 falhas** — praticamente todo
`create(:captain_assistant)` do projeto quebrou pela mesma validação. Depois do rollback,
voltou a 59.

### Como as atendentes em Hermes foram criadas então

Não pelo formulário. Pelo **Construtor** (`HermesBuilder` + `Captain::Mcp::Tools::SaveAgentSpecTool`),
que preenche `hermes_profile_name` e `hermes_webhook_base_url` corretamente. O formulário do
painel só serve pro caminho antigo.

### Opções para a próxima rodada

| Opção | O que é | Custo |
|---|---|---|
| **A** | Acrescentar `engine` + os dois campos Hermes ao formulário, e aí trocar o default | frontend pequeno + i18n en/pt_BR |
| **B** | Validar no ponto de ligação: `CaptainInbox` recusa atrelar inbox a assistant em `captain_interno` | menor, e é exatamente onde a armadilha mora |
| **C** | Nada em código — criar a atendente da academia pelo Construtor, que já faz certo | zero, mas depende de lembrar |

Recomendação: **B**. O default da coluna é irrelevante enquanto nenhum assistant interno
conseguir ser atrelado a uma inbox — que é o dano real. E não mexe no fluxo de criação.

**Decisão do Rodrigo (22/08/2026): opção C.** Nada em código. Ele cria a atendente da academia
pelo Construtor, que já preenche `hermes_profile_name` e `hermes_webhook_base_url` corretamente.
O formulário do painel fica como está.

---

## F1 em staging — validado (22/08/2026, 15:53 BRT)

Stack `iachat-v2` (já existia, estava escalada a 0), imagem `ghcr.io/rodribm10/iachat:v235`,
DNS `iachatv2.hoteis1001noites.com.br`, banco `iachat_staging` isolado.

O teste que importava não era "sobe num banco limpo" — era **rodar a migration contra o schema e
o dado reais de produção**. Por isso restaurei um dump do prod (420 MB, `pg_dump` somente
leitura) no staging antes de migrar.

### Resultado

| Verificação | Resultado |
|---|---|
| Migration contra dado real de produção | rodou em **0,13s**, sem erro |
| Tabelas | 135 → **110** (as 25 saíram) |
| Conversas / contatos / mensagens | 23.738 / 15.878 / 318.658 — **intactos** |
| Reservas / cobranças PIX / assistants | 354 / 213 / 18 — **intactos** |
| Erro no boot do app | **nenhum** |
| HTTPS | **200** |
| `tools/list` do MCP (superfície do Hermes) | **19 tools**, todas presentes |
| Credencial Codex ativa | **1** — o que eu quase deletei continua de pé |

### Atenção

O `iachat_staging` agora contém **uma cópia dos dados reais de clientes** (contatos, telefones,
conversas). Está na mesma VPS, em banco isolado, atrás do mesmo Traefik. Quando a validação
terminar, o certo é escalar a stack de volta a 0 e recriar o banco vazio.

### Pendente pra produção

Só falta a janela. Hoje é sábado 15:53 BRT — pico da operação. **Não subir agora.**
Ordem em produção, quando for: merge pra `main` → CI builda → deploy do **código** → validar →
só então rodar a **migration**.
