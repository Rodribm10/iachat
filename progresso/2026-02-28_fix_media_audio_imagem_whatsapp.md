# Troubleshooting: Áudio e Imagem não aparecem no Chatwoot (WhatsApp via WuzAPI)

**Data:** 2026-02-28
**Branch:** fix-media-audio-v2
**Canal:** WhatsApp via WuzAPI

---

## Sintomas

- Áudio exibe `00:00 / 00:00` e não toca
- Imagem exibe "Esta imagem não está mais disponível"
- Mensagens de texto chegam normalmente
- Transcrição do áudio aparece corretamente, mas o áudio não toca

---

## ⚡ Diagnóstico Rápido (comece aqui)

Antes de ler tudo, rode esses comandos na ordem. O primeiro que falhar identifica o bug.

```bash
# 1. Arquivo chegou? Descriptografia OK?
grep -E "WuzAPI Decrypt|SUCCESS|invalid format" log/development.log | tail -5

# 2. Arquivo está no disco?
bin/rails runner "a = Attachment.last; puts a.file.blob.byte_size; puts File.binread(ActiveStorage::Blob.service.path_for(a.file.blob.key), 4).bytes.map{|b| '%02X'%b}.join(' ')"

# 3. URL que o browser recebe é relativa ou absoluta?
grep "data_url" log/development.log | tail -3
```

**Interpretação:**
| Resultado | Bug |
|-----------|-----|
| Sem `WuzAPI Decrypt:` nos logs | Bug 5 (PayloadParser sem `attachment_params`) |
| `WuzAPI Decrypt Error: NoMethodError` | Bug 3 (`update!` em vez de `update`) |
| Bytes: `31 88 d2` ou similares (não FF D8, 4F 67, 89 50) | Bug 2 (arquivo encriptado) |
| URL absoluta `https://ngrok-url/...` | Bug 4 (ngrok interstitial — ver abaixo) |
| URL relativa `/rails/active_storage/...` e bytes válidos | Bug de infra (Sidekiq parado, ngrok caído) |

---

## Diagnóstico — Root Causes

Havia **seis bugs independentes** documentados ao longo do tempo. Os primeiros três são históricos. Os outros três surgiram com refatorações.

---

### Bug 1 — URL de mídia apontando para `localhost` hardcoded *(histórico)*

**Arquivo:** `app/models/attachment.rb`

**Problema:**
`file_url` e `thumb_url` geravam URLs hardcoded com `localhost:3000`. O browser acessando via ngrok não consegue resolver `localhost:3000` diretamente.

```ruby
# QUEBRADO:
rails_storage_proxy_url(file, host: 'localhost:3000', protocol: 'http')
```

**Resolvido em:** commit `6b214b38d` — passou a usar `dev_url_options` que lê `FRONTEND_URL`.

---

### Bug 2 — Arquivo de mídia salvo criptografado *(histórico)*

**Arquivo:** `app/services/whatsapp/incoming_message_wuzapi_service.rb` + `decryption_service.rb`

**Problema:**
O fluxo de download tinha 3 métodos em cascata:

| Método | O que faz | Status |
|--------|-----------|--------|
| Method 1 | WuzAPI `/chat/downloadimage` endpoint | ❌ Sempre falhava com `502 Bad Gateway` |
| Method 2 | `DecryptionService` com `Net::HTTP` | ❌ `Net::HTTP` não segue redirects → `nil` silencioso |
| Method 3 | `Down.download` direto do CDN | ⚠️ Baixava mas salvava bytes **encriptados** |

O arquivo no disco começava com bytes aleatórios (`31 88 d2...`) em vez de `FF D8 FF` (JPEG) ou `4F 67 67 53` (OGG).

**Correção:** Unificar Methods 2+3: `Down.download` (que segue redirects) → descriptografar → salvar.

**Resolvido em:** commit `6b214b38d`

---

### Bug 3 — `OpenSSL::Cipher#update!` não existe em Ruby *(histórico)*

**Arquivo:** `app/services/whatsapp/decryption_service.rb`

```ruby
# QUEBRADO:
decipher.update!(data) + decipher.final

# CORRETO:
decipher.update(data) + decipher.final
```

**Resolvido em:** commit `6b214b38d`

---

### Bug 4 — ngrok interstitial bloqueia mídia no browser *(recorrente — leia com atenção)*

**Arquivo:** `app/models/attachment.rb`

**Problema:**
Mesmo com o Bug 1 corrigido, a URL da mídia era gerada como absoluta com o host do ngrok:
```
https://SEU-NGROK.ngrok-free.dev/rails/active_storage/blobs/proxy/.../file.ogg
```

O ngrok exibe uma **página HTML de aviso** para qualquer request de browser sem o cookie ngrok válido. Quando `<img src="ngrok-url">` ou `<audio src="ngrok-url">` é carregado:
- O browser não tem o cookie ngrok (acessando Chatwoot via `http://localhost:3000`)
- O ngrok retorna HTML de interstitial em vez do arquivo
- O browser tenta parsear HTML como imagem/áudio → falha silenciosamente
- Imagem: `@error` → `hasError = true` → "Esta imagem não está mais disponível"
- Áudio: nenhum dado decodificável → `loadedmetadata` nunca dispara → `duration = 0` → "00:00 / 00:00"

**Diagnóstico:**
```bash
# Via curl (não usa User-Agent de browser → bypassa interstitial):
curl -s -w "HTTP: %{http_code} Size: %{size_download}\n" -o /dev/null "URL_DO_ARQUIVO"
# → HTTP: 200 Size: 5968 (arquivo chegou via curl!)

# Mas no browser a mídia não carrega → é o interstitial do ngrok
```

**Por que curl funciona mas browser não?**
O ngrok detecta browser pelo `User-Agent` header. Curl não envia User-Agent de browser, então recebe o arquivo direto. O browser envia `User-Agent: Mozilla/5.0...` e recebe a página de aviso.

**Correção:** Usar URL **relativa** em vez de absoluta. O browser resolve contra o servidor atual — sem passar pelo ngrok:

```ruby
# ANTES (absoluta com ngrok → interstitial):
rails_storage_proxy_url(file, **dev_url_options)
# → https://seu-ngrok.ngrok-free.dev/rails/active_storage/blobs/proxy/TOKEN/file.ogg

# DEPOIS (relativa → carrega diretamente do servidor):
rails_storage_proxy_path(file)
# → /rails/active_storage/blobs/proxy/TOKEN/file.ogg
```

Aplicar em `file_url` **e** `thumb_url`:
```ruby
def file_url
  return '' unless file.attached?

  if Rails.env.development?
    rails_storage_proxy_path(file)   # ← relativo, sem host
  else
    url_for(file)
  end
end

def thumb_url
  return '' unless file.attached? && image?
  begin
    representation = file.representation(resize_to_fill: [250, nil])
    if Rails.env.development?
      rails_storage_proxy_path(representation)   # ← relativo, sem host
    else
      url_for(representation)
    end
  rescue ActiveStorage::UnrepresentableError => e
    Rails.logger.warn "Unrepresentable image: #{id} - #{e.message}"
    ''
  end
end
```

**Por que funciona:**
- Browser em `http://localhost:3000` → `/rails/...` → resolve para `http://localhost:3000/rails/...` → Rails serve direto
- Browser em `https://ngrok-url/` → `/rails/...` → resolve para `https://ngrok-url/rails/...` → ngrok já tem cookie → funciona

**Resolvido em:** commit `cfa2dc71b`

---

### Bug 5 — Refactoring removeu métodos críticos do PayloadParser *(recorrente)*

**Arquivo:** `app/services/whatsapp/providers/wuzapi/payload_parser.rb`

**Problema:**
O commit de refactoring `c48047ba5` ("modulariza processamento de mídias e payloads para conformidade com RuboCop") extraiu código para novos arquivos mas **acidentalmente removeu** dois métodos públicos do `PayloadParser` que eram chamados externamente:

- `text_content` → usado em `incoming_message_wuzapi_service.rb:140,154`
- `attachment_params` → usado em `incoming_message_wuzapi_service.rb:attach_files`

**Sintoma:**
```
NoMethodError: undefined method 'text_content' for an instance of Whatsapp::Providers::Wuzapi::PayloadParser
```
Todas as mensagens de texto falhavam. Mídia falhava silenciosamente (rescuado em `attach_files`).

**Como detectar:**
```bash
grep "NoMethodError.*text_content\|NoMethodError.*attachment_params" log/development.log | tail -5
```

**Correção:** Restaurar os dois métodos no `PayloadParser`. Ver commit `ec6cfc317` e `e6e4c3652` para o código completo.

**Onde ficam os métodos:**
- `text_content` — extrai texto do payload (conversation, extendedText, caption de mídia)
- `attachment_params` — extrai URL, filename, mimetype, mediaKey da mídia
- **Arquivo atual:** `app/services/whatsapp/providers/wuzapi/payload_parser.rb`

**Resolvido em:** commits `e6e4c3652` + `ec6cfc317`

---

### Bug 6 — Audio salvo com content-type `audio/opus` em vez de `audio/ogg`

**Arquivo:** `app/services/whatsapp/wuzapi/media_handler.rb` + `app/models/attachment.rb`

**Problema:**
O WhatsApp envia áudio como **container OGG com codec Opus** (bytes `OggS` = `4F 67 67 53`). O WuzAPI declarava `mimetype: audio/ogg; codecs=opus` ou `audio/opus`. Browsers não conseguem reproduzir um container OGG declarado como `audio/opus` (raw Opus).

```bash
# Confirmar via Rails console:
a = Attachment.find(ID)
a.file.blob.content_type   # → "audio/opus" (errado)
File.binread(ActiveStorage::Blob.service.path_for(a.file.blob.key), 4)
# → "\x4FOggS" (é OGG, não Opus raw)
```

**Correção em `media_handler.rb`** — normalizar ao salvar:
```ruby
def sanitize_content_type(mimetype, type)
  return 'audio/ogg' if type == :audio && mimetype.to_s.include?('opus')
  mimetype || 'application/octet-stream'
end
```

**Correção em `attachment.rb`** — normalizar blobs antigos na primeira leitura:
```ruby
def audio_metadata
  normalize_opus_blob_content_type!   # corrige blobs salvos com audio/opus
  # ...
end

def normalize_opus_blob_content_type!
  blob = file.blob
  return unless blob.content_type == 'audio/opus'
  blob.update_column(:content_type, 'audio/ogg')
end
```

**Resolvido em:** commit `5d3ce4e56`

---

## Estado correto após todos os fixes

### `app/models/attachment.rb`
- `file_url`: usa `rails_storage_proxy_path(file)` em dev (URL relativa)
- `thumb_url`: usa `rails_storage_proxy_path(representation)` em dev (URL relativa)
- `audio_metadata`: chama `normalize_opus_blob_content_type!` para corrigir blobs antigos
- `normalize_opus_blob_content_type!`: atualiza `audio/opus` → `audio/ogg` no blob
- Em produção: comportamento inalterado com `url_for(file)`

### `app/services/whatsapp/wuzapi/media_handler.rb`
- `sanitize_content_type`: normaliza `audio/opus` → `audio/ogg` para novos uploads
- `detect_extension`: retorna `.ogg` para audio (não `.mp3`)
- `final_filename`: força `.ogg` se audio chegou com extensão `.mp3`

### `app/services/whatsapp/providers/wuzapi/payload_parser.rb`
- `text_content`: presente e funcional
- `attachment_params`: presente e funcional
- `UndecryptableMessage`: na lista de eventos ignoráveis

### `app/services/whatsapp/decryption_service.rb`
- Constructor aceita `(media_key, media_type)` — sem URL (download separado)
- Método principal: `decrypt_bytes(encrypted_bytes)` — recebe bytes já baixados
- Algoritmo: HKDF SHA-256 → AES-256-CBC → fallback AES-256-CTR
- Usa `decipher.update(data)` (sem `!`)

### `config/environments/development.rb`
```ruby
config.active_storage.resolve_model_to_route = :rails_storage_proxy
```

### `vite.config.ts`
```javascript
server: {
  proxy: {
    '/rails': {
      target: 'http://127.0.0.1:3000',
      changeOrigin: true,
    },
  },
},
```

---

## Checklist de diagnóstico completo

### 1. Mensagens de texto chegam? (PayloadParser OK?)

```bash
grep "NoMethodError.*PayloadParser\|undefined method.*text_content\|undefined method.*attachment_params" log/development.log | tail -5
```
❌ Encontrou → Bug 5 (métodos removidos do PayloadParser)

---

### 2. Verificar URLs geradas

```bash
grep "data_url" log/development.log | tail -3
```

✅ Deve aparecer URL **relativa**: `/rails/active_storage/blobs/proxy/...`
❌ URL absoluta com ngrok `https://SEU-NGROK.../...` → Bug 4 (interstitial) — trocar para `rails_storage_proxy_path`
❌ URL com `localhost:3000` hardcoded → Bug 1 (versão antiga)

---

### 3. Verificar se o arquivo está encriptado

```bash
bin/rails runner "
a = Attachment.last
key = ActiveStorage::Blob.service.path_for(a.file.blob.key)
bytes = File.binread(key, 4).bytes.map { |b| format('%02X', b) }.join(' ')
puts \"#{a.id} #{a.file_type} content_type=#{a.file.blob.content_type} bytes=#{bytes}\"
"
```

- `FF D8 FF` → JPEG válido ✅
- `89 50 4E 47` → PNG válido ✅
- `4F 67 67 53` (OggS) → OGG válido ✅
- Qualquer outra coisa → arquivo encriptado ❌ → Bug 2

---

### 4. Verificar logs de descriptografia

```bash
grep -E "WuzAPI Decrypt|SUCCESS|invalid format|first bytes|Endpoint download|CDN download" log/development.log | tail -10
```

- `WuzAPI Decrypt: SUCCESS - Valid media detected` ✅
- `WuzAPI: Endpoint download failed - API Error: 502` → normal, fallback ativo ✅
- `WuzAPI Decrypt: Decrypted but invalid format (first bytes: XX XX XX XX)` → algoritmo errado
- `WuzAPI Decrypt Error: NoMethodError` → Bug 3 (`update!` em vez de `update`)
- Nenhuma linha `WuzAPI Decrypt:` → `mediaKey` ausente no payload OU Bug 5

---

### 5. Verificar content-type do blob de áudio

```bash
bin/rails runner "Attachment.where(file_type: 1).last(3).each { |a| puts \"#{a.id} ct=#{a.file.blob.content_type}\" }"
```

- `audio/ogg` ✅
- `audio/opus` → Bug 6 (normalizado lazily em `audio_metadata`, ou corrigir via migração)
- `application/octet-stream` → `sanitize_content_type` não está rodando (checar `media_handler.rb`)

---

### 6. Verificar se o Sidekiq está rodando e processando

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

### 7. Verificar se o arquivo existe no disco

```bash
# No Rails console:
Attachment.last.file.attached?  # deve ser true
Attachment.last.file.blob.service.exist?(Attachment.last.file.blob.key)  # deve ser true
```

`ActiveStorage::FileNotFoundError` no log = blob existe no banco mas arquivo não está no disco = upload falhou silenciosamente.

---

### 8. Testar URL diretamente (bypass browser)

```bash
# Substitua pela URL do attachment que falha (via log ou Rails console)
curl -s -w "HTTP: %{http_code} CT: %{content_type} Size: %{size_download}\n" -o /dev/null "/rails/active_storage/blobs/proxy/TOKEN/file.ogg"
# Ou via URL absoluta local:
curl -s -w "HTTP: %{http_code} CT: %{content_type} Size: %{size_download}\n" -o /dev/null "http://localhost:3000/rails/active_storage/blobs/proxy/TOKEN/file.ogg"
```

- HTTP 200, Size > 0 → arquivo acessível ✅
- HTTP 404 → blob não existe no disco
- HTTP 200, Size = 0 → HEAD request (usar curl sem -I)

---

## Dependências críticas

| Variável/Config | Onde | Valor esperado em dev |
|-----------------|------|-----------------------|
| `FRONTEND_URL` | `.env` | `https://SEU-URL.ngrok-free.dev` (usado para webhooks) |
| `ACTIVE_STORAGE_SERVICE` | `.env` | `local` |
| `resolve_model_to_route` | `config/environments/development.rb` | `:rails_storage_proxy` |
| Vite proxy `/rails` | `vite.config.ts` | `target: http://127.0.0.1:3000` |
| `mediaKey` | Payload WuzAPI | Obrigatório para descriptografia |

---

## Notas de arquitetura

- O WhatsApp **sempre** encripta mídia no CDN (arquivos `.enc`)
- A chave (`mediaKey`) é entregue no payload do webhook junto com a URL
- Sem `mediaKey` não é possível descriptografar — o arquivo vai aparecer corrompido
- O WuzAPI endpoint `/chat/downloadimage` deveria retornar mídia já descriptografada (Method 1), mas está com instabilidade (502). O fallback via HKDF+AES é a solução robusta.
- Em **produção** (sem ngrok), `url_for(file)` usa `default_url_options` configurado corretamente — sem interstitial.
- **URL relativa vs absoluta em dev:** `rails_storage_proxy_path` é mais robusto que `rails_storage_proxy_url` pois funciona independente de onde o browser esteja acessando.
- **Refactoring é perigoso aqui:** os métodos `text_content` e `attachment_params` no `PayloadParser` são contratos públicos chamados por `incoming_message_wuzapi_service.rb`. Qualquer refactoring deve verificar todos os callers externos.
