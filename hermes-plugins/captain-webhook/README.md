# captain-webhook

Hermes Agent platform plugin que **substitui** o `WebhookAdapter` built-in pra suportar **session_chat_id estável** derivado de campo no payload.

## Por que existe

O webhook adapter built-in do Hermes monta a chave de sessão como:

```
session_chat_id = f"webhook:{route_name}:{delivery_id}"
```

`delivery_id` é único por POST → cada mensagem cria sessão nova no Hermes. Isso funciona pra webhooks one-shot (alertas, GitHub events), mas é **errado pra integração de chat** onde múltiplas mensagens da mesma conversa precisam compartilhar memória de sessão.

Esse plugin permite que o caller (ex: Captain) inclua um identificador estável no payload — `conversation_id` (preferido) ou `hermes_session_id` — e o adapter reescreve a chave pra:

```
session_chat_id = f"webhook:{route_name}:session:{conversation_id}"
```

Mesmo `conversation_id` em múltiplas POSTs → mesma sessão Hermes → memória da conversa preservada.

## Como funciona

`CaptainWebhookAdapter` herda de `WebhookAdapter` built-in e faz **uma única override**: o método `handle_message()`. Ele:

1. Recebe o `event` já montado pelo built-in
2. Lê `event.raw_message` (o payload JSON do webhook)
3. Se houver `hermes_session_id` ou `conversation_id`, monta novo `chat_id`
4. Mirror o `_delivery_info` pra nova chave (pra o `send()` posterior achar config)
5. Modifica `event.source.chat_id`
6. Chama `super().handle_message(event)`

Toda outra lógica (HMAC, rate limit, idempotency, parsing JSON, signature validation, deliver dispatch) é herdada **sem cópia**.

## Como o Hermes substitui o built-in

`gateway/run.py`:
```python
# Plugin-registered platforms (checked first)
if platform_registry.is_registered(platform.value):
    adapter = platform_registry.create_adapter(platform.value, config)
    if adapter is not None:
        return adapter
# Fall through to built-in adapters below
```

Se este plugin se registrar com `name="webhook"` (mesmo nome do built-in), `is_registered("webhook")` retorna `True` e o `CaptainWebhookAdapter` é usado em vez do built-in `WebhookAdapter`.

## Instalação no profile do Hermes

```bash
# Copia plugin pro profile
cp -r hermes-plugins/captain-webhook /root/.hermes/profiles/<profile>/plugins/

# Ativa
HERMES_HOME=/root/.hermes/profiles/<profile> hermes plugins enable captain-webhook

# Reinicia gateway pra carregar
pkill -f "HERMES_HOME=/root/.hermes/profiles/<profile>"
HERMES_HOME=/root/.hermes/profiles/<profile> nohup hermes gateway run --replace > /var/log/hermes-<profile>.log 2>&1 &
```

Verifica:
```bash
HERMES_HOME=/root/.hermes/profiles/<profile> hermes plugins list | grep captain-webhook
```

## Backward compatibility

Quando o payload **NÃO traz** `hermes_session_id` nem `conversation_id`, o adapter **não modifica nada** — comportamento idêntico ao built-in. Webhooks one-shot continuam funcionando normalmente.

## Limitações

- O plugin estende a versão do `WebhookAdapter` instalada no Hermes. Quando o Hermes for atualizado, é prudente revisar se a interface base mudou (signature do `handle_message`, formato do `chat_id`, etc).
- Não modifica o ciclo de idempotency: cada POST ainda precisa de `delivery_id` único (auto-gerado pelo Hermes ou via header `X-Request-ID`).
- Não persiste sessions entre restarts do Hermes — isso é responsabilidade do session store do próprio Hermes (SQLite por profile).
