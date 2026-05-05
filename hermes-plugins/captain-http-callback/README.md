# captain-http-callback

Hermes Agent platform plugin que entrega a resposta do agente como `POST` HTTP a uma URL configurável.

## Por que existe

O Hermes nativamente entrega respostas em plataformas conhecidas (Telegram, Slack, Discord, WhatsApp, etc). Quando integramos o Hermes como cérebro de outro backend (no nosso caso o **Captain / Chatwoot**), precisamos da resposta de volta via HTTP para o backend continuar o fluxo (mandar pro cliente WhatsApp, atualizar conversa, etc) — esse plugin fornece essa ponte.

## Fluxo

```
1. Captain → POST /webhooks/<rota> no Hermes (entrada da mensagem do cliente)
2. Hermes processa via LLM (Codex/Anthropic/Gemini conforme config dele)
3. Hermes invoca este plugin com a resposta gerada
4. Plugin → POST <url-configurada> com a resposta
5. Captain recebe, identifica conversa, manda pro WhatsApp
```

## Instalação

Plugin é discovered automaticamente quando colocado em `~/.hermes/plugins/captain-http-callback/`. Após copiar os arquivos, reinicie o gateway:

```bash
pkill -f "hermes.*gateway" && sleep 2
nohup hermes gateway run --replace > /var/log/hermes-gateway.log 2>&1 &
```

Verifique:

```bash
hermes plugins list | grep http_callback
```

## Uso

Cria webhook subscription apontando para este deliver type:

```bash
hermes webhook subscribe minha-rota \
    --prompt "Cliente disse: {message}. Responda como ..." \
    --deliver http_callback \
    --deliver-chat-id "https://seu-backend.example/api/hermes_callback"
```

`--deliver-chat-id` é interpretado como a **URL de callback**. Quando o agente terminar de processar, este plugin POSTa nessa URL.

## Formato do POST de callback

```http
POST <url-configurada> HTTP/1.1
Content-Type: application/json; charset=utf-8
X-Hermes-Callback-Signature: sha256=<hex-hmac>     (opcional, se signing_secret configurado)

{
  "content": "<resposta gerada pelo agente>",
  "reply_to": "<id da mensagem original ou null>",
  "metadata": { ... },
  "timestamp": <unix epoch>
}
```

## Assinatura HMAC opcional

Define a env var `CAPTAIN_HTTP_CALLBACK_SECRET` em `~/.hermes/.env` (ou no shell do Hermes). Quando set, o plugin assina cada POST com `HMAC-SHA256(secret, body)` no header `X-Hermes-Callback-Signature`. O backend valida a assinatura antes de processar.

```bash
# em ~/.hermes/.env
CAPTAIN_HTTP_CALLBACK_SECRET=<gere com: openssl rand -hex 32>
```

## Limitações

- **Send-only.** Não recebe mensagens. A entrada da conversa precisa vir via outro adapter (geralmente o `webhook` adapter built-in).
- **Resposta esperada:** o backend precisa aceitar `POST` JSON e responder `2xx`. Plugin loga warning em qualquer status `>= 300` e retorna falha pro Hermes.
- **Timeout default:** 15s. Configurável via `extra.timeout_seconds` no `config.yaml`.
- **Sem retry built-in.** Se o backend retornar erro, é falha — o Hermes pode escolher logar e seguir. Adicione retry no backend caller se precisar.
