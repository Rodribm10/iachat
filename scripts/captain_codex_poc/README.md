# Captain Codex OAuth PoC

Proof-of-concept para validar se a assinatura do ChatGPT Plus pode ser usada no Captain AI via OAuth device flow, reutilizando o `client_id` do Hermes.

## Pré-requisitos

1. **Assinatura ChatGPT Plus ativa** na conta `borbamachadoo@gmail.com`
2. Ruby 3.x instalado (não precisa do bundle do Chatwoot — só stdlib)

## Passos

### 1) Login (device flow)

```bash
ruby scripts/captain_codex_poc/login.rb
```

- Vai imprimir uma URL + um código
- Abra a URL no browser, faça login com `borbamachadoo@gmail.com`, cole o código
- Script detecta a autorização e salva tokens em `scripts/captain_codex_poc/tokens.json`

### 2) Teste de chat simples

```bash
ruby scripts/captain_codex_poc/test_chat.rb
```

Faz uma chamada simples `POST /chat/completions` com `gpt-5.4` e imprime a resposta.

**Critério de sucesso:** resposta HTTP 200 com conteúdo coerente em português.

### 3) Teste de function calling

```bash
ruby scripts/captain_codex_poc/test_tools.rb
```

Faz chamada com uma tool `gerar_pix` simulada e verifica se o modelo:
- Reconhece que precisa chamar a tool
- Retorna `tool_calls` com `function.name` e `function.arguments` corretos

**Critério de sucesso:** `tool_calls` não-nulo e JSON de argumentos válido.

**Critério de go/no-go do projeto Codex OAuth:** se este teste falhar (modelo não suporta function calling via endpoint Codex), **abortamos a implementação**. Os tools do Captain (Pix, reservas, labels) são pré-requisito não-negociável.

### 4) Comparação de qualidade (manual)

```bash
ruby scripts/captain_codex_poc/test_jasmine_like.rb
```

Simula uma conversa estilo Jasmine — cliente pedindo reserva. Compare subjetivamente a resposta com o que a Jasmine faz hoje em produção com `gpt-4o`.

## Arquivos

- `login.rb` — device flow
- `test_chat.rb` — smoke test /chat/completions
- `test_tools.rb` — function calling
- `test_jasmine_like.rb` — qualidade conversacional
- `tokens.json` — access_token + refresh_token (git-ignored)
- `codex_client.rb` — helper compartilhado (refresh + HTTP)

## Segurança

O arquivo `tokens.json` contém credenciais OAuth reais e **NUNCA deve ser commitado**. Já está no `.gitignore` desta pasta.
