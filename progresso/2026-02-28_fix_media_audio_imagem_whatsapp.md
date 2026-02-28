# Troubleshooting: Áudio e Imagem não aparecem no Chatwoot (WhatsApp via WuzAPI)

**Data:** 2026-02-28
**Branch:** fix-media-audio-v2
**Canal:** WhatsApp via WuzAPI

---

## Sintomas

- Áudio exibe `00:00 / 00:00` e não toca
- Imagem exibe "Esta imagem não está mais disponível"
- Mensagens de texto chegam normalmente

---

## Diagnóstico — Root Causes

Havia **três bugs independentes**, todos precisavam ser corrigidos.

---

### Bug 1 — URL de mídia apontando para `localhost` (invisível via ngrok)

**Arquivo:** `app/models/attachment.rb`

**Problema:**
`file_url` e `thumb_url` geravam URLs hardcoded com `localhost:3000`. O browser acessando via ngrok não consegue resolver `localhost:3000` diretamente, então `<img>` e `<audio>` falhavam silenciosamente.

```ruby
# ANTES (quebrado):
rails_storage_proxy_url(file, host: 'localhost:3000', protocol: 'http')

# DEPOIS (correto):
rails_storage_proxy_url(file, **dev_url_options)

def dev_url_options
  uri = URI.parse(ENV.fetch('FRONTEND_URL', 'http://localhost:3000').chomp('/'))
  host = [80, 443].include?(uri.port) ? uri.host : "#{uri.host}:#{uri.port}"
  { host: host, protocol: uri.scheme }
end
```

**Efeito visual:**
- Imagem → `@error` → `hasError = true` → "Esta imagem não está mais disponível"
- Áudio → `onLoadedMetadata` nunca disparado → `duration = 0` → "00:00 / 00:00"

---

### Bug 2 — Arquivo de mídia salvo criptografado (sem descriptografar)

**Arquivo:** `app/services/whatsapp/incoming_message_wuzapi_service.rb` + `decryption_service.rb`

**Problema:**
O fluxo de download tinha 3 métodos em cascata:

| Método | O que faz | Status |
|--------|-----------|--------|
| Method 1 | WuzAPI `/chat/downloadimage` endpoint | ❌ Sempre falhava com `502 Bad Gateway` |
| Method 2 | `DecryptionService` com `Net::HTTP` | ❌ `Net::HTTP` não segue redirects — CDN do WhatsApp redireciona → `nil` silencioso |
| Method 3 | `Down.download` direto do CDN | ⚠️ Baixava mas salvava bytes **encriptados** |

O WhatsApp entrega mídia encriptada (AES-256-CBC) no CDN com URLs `.enc`. O Method 3 baixava os bytes encriptados corretamente mas os salvava sem descriptografar. O arquivo no disco era inválido.

Diagnóstico confirmado via `xxd`:
```
# JPEG começa com FF D8 FF
# Arquivo salvo começava com:
00000000: 3188 d20c 46ae 98f3 03bd...  ← bytes encriptados
```

**Correção:**
Unificar Methods 2+3: usar `Down.download` (que segue redirects) para baixar os bytes, depois descriptografar em memória antes de salvar.

```ruby
# DEPOIS:
encrypted_tempfile = Down.download(media_url, ...)
encrypted_bytes = encrypted_tempfile.read.b

if attachment_data[:media_key].present?
  decrypted = Whatsapp::DecryptionService.new(
    attachment_data[:media_key],
    file_content_type(message_type)
  ).decrypt_bytes(encrypted_bytes)
  return decrypted if decrypted
end

StringIO.new(encrypted_bytes)  # fallback
```

---

### Bug 3 — `OpenSSL::Cipher#update!` não existe em Ruby

**Arquivo:** `app/services/whatsapp/decryption_service.rb`

**Problema:**
O método de descriptografia usava `decipher.update!(data)` mas Ruby só tem `decipher.update(data)` (sem `!`). Causava `NoMethodError` em todo attempt de descriptografia.

```ruby
# ANTES (quebrado):
decipher.update!(data) + decipher.final

# DEPOIS (correto):
decipher.update(data) + decipher.final
```

---

## Estado correto após os fixes

### `app/models/attachment.rb`
- `file_url` e `thumb_url` usam `dev_url_options` que lê `FRONTEND_URL` do `.env`
- Em produção (`else`): comportamento inalterado com `url_for(file)`

### `app/services/whatsapp/incoming_message_wuzapi_service.rb`
- Method 1: WuzAPI endpoint (funciona quando disponível)
- Method 2+3 unificados: `Down.download` → decrypt com `mediaKey` → fallback raw

### `app/services/whatsapp/decryption_service.rb`
- Constructor aceita `(media_key, media_type)` — sem URL (download separado)
- Método principal: `decrypt_bytes(encrypted_bytes)` — recebe bytes já baixados
- Algoritmo: HKDF SHA-256 → AES-256-CBC → fallback AES-256-CTR
- Loga os primeiros bytes se o formato não for reconhecido (facilita debug futuro)

---

## Checklist de diagnóstico (quando áudio/imagem não funcionar)

### 1. Verificar URLs geradas

```bash
grep "data_url" log/development.log | tail -3
```

Deve aparecer: `https://SEU-NGROK.ngrok-free.dev/rails/active_storage/...`
❌ Se aparecer `http://localhost:3000/...` → Bug 1 voltou (checar `FRONTEND_URL` no `.env`)

---

### 2. Verificar se o arquivo está encriptado

```bash
# Pegar o blob key do arquivo (via Rails console ou log)
xxd storage/XX/XX/BLOB_KEY | head -2
```

- `FF D8 FF` → JPEG válido ✅
- `89 50 4E 47` → PNG válido ✅
- `4F 67 67 53` (OggS) → OGG válido ✅
- Qualquer outra coisa → encriptado ❌

---

### 3. Verificar logs de descriptografia

```bash
grep -E "WuzAPI Decrypt|SUCCESS|invalid format|first bytes" log/development.log | tail -10
```

- `WuzAPI Decrypt: SUCCESS - Valid media detected` ✅
- `WuzAPI Decrypt: Decrypted but invalid format (first bytes: XX XX XX XX)` → algoritmo errado — os bytes revelam o tipo real
- `WuzAPI Decrypt Error: NoMethodError` → bug no Ruby (checar `update` vs `update!`)
- Nada aparece após "Attempting local decryption" → mediaKey ausente no payload do WuzAPI

---

### 4. Verificar se o Sidekiq está rodando e processando

```bash
ps aux | grep sidekiq | grep -v grep
```

Deve aparecer **somente uma linha** com `[N of 12 busy]` **sem** `stopping`.

Se aparecer `stopping` ou dois processos:
```bash
pkill -f sidekiq
rm -f .overmind.sock
pnpm run dev
```

---

### 5. Verificar se o arquivo existe no disco

```bash
# No Rails console:
Attachment.last.file.attached?  # deve ser true
Attachment.last.file.blob.service.exist?(Attachment.last.file.blob.key)  # deve ser true
```

`ActiveStorage::FileNotFoundError` no log = blob existe no banco mas arquivo não está no disco = o upload falhou silenciosamente.

---

### 6. Verificar status do WuzAPI endpoint de download

```bash
grep "WuzAPI: Endpoint download failed" log/development.log | tail -3
```

Se aparece `502 Bad Gateway` sistematicamente → WuzAPI `/chat/downloadimage` está down.
Isso é esperado e o sistema cai automaticamente para Method 2+3 (download direto + decrypt).

---

## Dependências críticas

| Variável | Onde | Valor esperado em dev com ngrok |
|----------|------|---------------------------------|
| `FRONTEND_URL` | `.env` | `https://SEU-URL.ngrok-free.dev` |
| `ACTIVE_STORAGE_SERVICE` | `.env` | `local` |
| `mediaKey` | Payload WuzAPI | Obrigatório para descriptografia |

---

## Notas de arquitetura

- O WhatsApp **sempre** encripta mídia no CDN (arquivos `.enc`)
- A chave (`mediaKey`) é entregue no payload do webhook junto com a URL
- Sem `mediaKey` não é possível descriptografar — o arquivo vai aparecer corrompido
- O WuzAPI endpoint `/chat/downloadimage` deveria retornar mídia já descriptografada (Method 1), mas está com instabilidade (502). O fallback via HKDF+AES é a solução robusta.
- Em **produção** (sem ngrok), o Bug 1 não existe pois `url_for(file)` usa `default_url_options` configurado corretamente.
