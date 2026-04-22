# Captain AI via OAuth ChatGPT Plus (Codex)

Documentação do caminho ponta-a-ponta pra fazer o Captain AI rodar usando a
**assinatura ChatGPT Plus** em vez de API key OpenAI paga por token.

Status: **funcional em dev** (2026-04-22). Pendente: rollout em staging/prod.

---

## Arquitetura

```
Captain (RubyLLM / Agents gem / ruby-openai)
         │
         │  POST /v1/chat/completions  (formato OpenAI Chat Completions)
         ▼
┌──────────────────────────────────────────────────────┐
│  Api::Internal::CodexProxyController                 │
│    • traduz chat→responses                           │
│    • Captain::Codex::AuthService.valid_access_token  │  (OAuth refresh automático)
│    • streaming SSE → agregado                        │
│    • retry em erros transitórios                     │
│    • traduz responses→chat                           │
└──────────────────────────────────────────────────────┘
         │
         │  POST https://chatgpt.com/backend-api/codex/responses
         │  Authorization: Bearer <OAuth token>
         ▼
    OpenAI Codex (consome assinatura ChatGPT Plus, sem cobrar por token)
```

**Embeddings NÃO passam pelo proxy.** O endpoint Codex não expõe `/embeddings`,
então `Captain::Llm::EmbeddingService` força o uso da OpenAI API tradicional
(requer `CAPTAIN_OPEN_AI_API_KEY` válida mesmo em modo Codex).

**Files API NÃO passa pelo proxy.** Mesmo motivo — `Llm::LegacyBaseOpenAiService`
(usado em `PdfProcessingService` e `PaginatedFaqGeneratorService`) continua
apontando pra OpenAI tradicional.

---

## Componentes

| Componente | Papel |
|------------|-------|
| `Captain::CodexCredential` (model) | Tabela singleton com access_token + refresh_token (AR encrypted) |
| `Captain::Codex::AuthService` | Device flow OAuth + refresh automático |
| `Captain::Codex::Client` | HTTP client streaming SSE, com retry em server_error |
| `Captain::Codex::Translator` | Chat Completions ↔ Responses API (bidirectional) |
| `Api::Internal::CodexProxyController` | `POST /codex/v1/chat/completions` |
| `Captain::Llm::ProviderConfig` | Single source of truth de provider/model/api_base |
| `Captain::Codex::RefreshTokensJob` | Sidekiq cron: refresh proativo de tokens (30min) |
| `rake captain:codex:{login,status,refresh}` | Utilitários de ops |

---

## Setup em dev

### 1. Migration

```bash
bundle exec rails db:migrate
```

### 2. Login OAuth (device flow)

```bash
bundle exec rails captain:codex:login
```

Abre URL no browser → loga com conta ChatGPT Plus → cola código → tokens
salvos em `captain_codex_credentials`.

### 3. Ativar o provider + configurar modelo

```ruby
# via rails runner ou bundle exec rails c
InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_LLM_PROVIDER').update!(
  value: 'openai_codex_oauth', locked: false
)
InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_CODEX_PROXY_URL').update!(
  value: 'http://localhost:3000/codex', locked: false
)
InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_MODEL').update!(value: 'gpt-5.2')
InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: 'sk-<KEY_VALIDA>')
```

**Importante sobre CAPTAIN_OPEN_AI_API_KEY:** mesmo em modo Codex OAuth, a key
precisa ser válida — é usada apenas pra embeddings (`/embeddings` não existe no
Codex) e file uploads. Sem essa key, `faq_lookup` e memory recall falham.

### 4. Reinicia Rails

```bash
pkill -9 -f 'overmind|vite|sidekiq|rails' 2>/dev/null; sleep 3
rm -f ./.overmind.sock && pnpm run dev
```

### 5. Teste direto no proxy

```bash
curl -X POST http://localhost:3000/codex/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.2","messages":[{"role":"user","content":"Diga: OK"}]}'
```

Espera: JSON no formato OpenAI Chat Completions com `choices[0].message.content`.

---

## Modelos suportados

O endpoint Codex via ChatGPT Plus aceita os modelos da família GPT-5 do Hermes:

| Modelo | Uso | RubyLLM reconhece? |
|--------|-----|--------------------|
| `gpt-5.2` | **Default atual** — conversação | ✓ |
| `gpt-5.1` | Fallback conversacional | ✓ |
| `gpt-5-codex`, `gpt-5.1-codex`, `gpt-5.1-codex-max`, `gpt-5.1-codex-mini` | Code-focused | ✓ |
| `gpt-5.4`, `gpt-5.3-codex` | Mais novos, melhor qualidade | ✗ (não no catalog do gem) |
| `gpt-4o`, `gpt-4o-mini` | **NÃO funciona** no endpoint Codex | — |

Pra usar `gpt-5.4`/`gpt-5.3-codex` no futuro: adicionar sobrescrita no proxy
que mapeia modelo recebido → modelo enviado ao Codex (evita validação do RubyLLM).

---

## Peculiaridades da Responses API (vs Chat Completions)

O Translator lida com as seguintes diferenças:

| Campo | Chat Completions | Responses |
|-------|------------------|-----------|
| Path | `/chat/completions` | `/responses` |
| Mensagens | `messages: []` | `input: []` |
| System prompt | `{role: "system", content: "..."}` | `instructions: "..."` (top-level, obrigatório) |
| Tools wrapper | `{type: "function", function: {name, description, parameters}}` | `{type: "function", name, description, parameters, strict}` |
| Tool result | `{role: "tool", tool_call_id, content}` | `{type: "function_call_output", call_id, output}` |
| Assistant tool_call | `{role: "assistant", tool_calls: [...]}` | `{type: "function_call", call_id, name, arguments}` |
| Streaming | Opcional (`stream: true`) | **Obrigatório** |
| `temperature`/`top_p` | Aceitos | **Rejeitados** (modelos reasoning) |
| `max_tokens` | `max_tokens` | `max_output_tokens` |
| Output final | `choices[].message` | `output: [items]` via SSE events |
| Storage | Default persiste | `store: false` **obrigatório** |

---

## Troubleshooting

### Erro: `"Stream must be set to true"`
Request enviou `stream: false`. O Translator força `stream: true` — verifique
se não há caminho que bypassa o Translator.

### Erro: `"The '<model>' model is not supported when using Codex with a ChatGPT account."`
Algum service está com modelo hardcoded inaceitável (gpt-4o, gpt-4o-mini).
Verifique `CAPTAIN_OPEN_AI_MODEL` e `CAPTAIN_OPEN_AI_MODEL_SCENARIO`.

### Erro: `"RubyLLM::ModelNotFoundError: Unknown model: <model>"`
O modelo não está no catalog do RubyLLM. Use `gpt-5.2` ou `gpt-5.1` (lista atual
em `RubyLLM.models.all.map(&:id)`).

### Erro: `"Incorrect API key provided"` em embedding
`CAPTAIN_OPEN_AI_API_KEY` inválida. Embeddings sempre usam OpenAI tradicional,
mesmo em Codex OAuth.

### Erro: `"response.failed" com code=server_error`
Instabilidade do endpoint Codex ou rate limit da assinatura Plus. O Client
já retenta 2x com backoff (0.5s, 1.5s). Se persistir, pode ser sinal de que
precisa subir de plano (Team/Pro).

### Voltar pra API tradicional (rollback rápido)

```ruby
InstallationConfig.find_by!(name: 'CAPTAIN_LLM_PROVIDER').update!(value: 'openai_api')
InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_MODEL').update!(value: 'gpt-4o-mini')
```

Depois restart.

---

## Ordem de commits (historical)

Branch: `feat/captain-codex-oauth`

1. `chore(captain): PoC Codex OAuth device flow + Responses streaming`
   — PoC standalone em Ruby puro (scripts/captain_codex_poc/)

2. `feat(captain): Codex OAuth auth module + proxy controller`
   — Migration, AuthService, Translator, Client, Controller

3. `fix(captain): always include instructions in Codex responses body`
   — Codex exige `instructions` mesmo quando não tem system message

4. `feat(captain): feature flag CAPTAIN_LLM_PROVIDER + ProviderConfig central`
   — Toggle openai_api vs openai_codex_oauth

5. `fix(captain): route embeddings to legacy OpenAI + retry transient errors`
   — Embeddings via OpenAI tradicional + retry automático no Client

---

## Riscos conhecidos

- **ToS**: uso comercial da assinatura ChatGPT Plus via OAuth não-oficial viola
  os termos da OpenAI. OpenAI pode cortar a conta sem aviso, derrubando todos
  os hotéis ao mesmo tempo.
- **Rate limits não documentados**: ChatGPT Plus tem limites de mensagens/hora
  que não são públicos. Pode bater limite em horário de pico.
- **Client_id do Hermes**: reusamos `app_EMoamEEZ73f0CkXaXp7hrann`. Se o Hermes
  regerar o app ou a OpenAI bloquear por terceiros, quebra.
- **Modelos Codex**: otimizados pra código. Qualidade conversacional pode ser
  inferior ao gpt-4o em alguns cenários.
- **Fallback não automático**: se o Codex falhar persistentemente, alternância
  pra `openai_api` é manual. Rollout em prod deve considerar automação.
