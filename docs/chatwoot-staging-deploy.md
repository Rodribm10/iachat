# Chatwoot — Deploy de branch em staging paralela

Runbook pra subir qualquer branch do fork `iachat` como stack Swarm paralela
isolada da produção, testar, e só depois fazer merge pra main.

> **Automação:** existe uma skill do Claude Code que executa esse runbook
> passo a passo. Invoque com "subir branch X em staging" no chat. Arquivos:
> `~/.claude/skills/chatwoot-staging-deploy/`. Este doc é o backup versionado
> pra quando não for usar a skill.

## Arquitetura atual

- **Repo:** `github.com/rodribm10/iachat` (fork do Chatwoot)
- **VPS:** `root@76.13.174.155` (Leo), Docker Swarm + Traefik v2.11 + Let's Encrypt
- **Prod:** stack `iachat` em `iachat.hoteis1001noites.com.br`, imagem `ghcr.io/rodribm10/iachat:vN`
- **Workflow CI:** `.github/workflows/deploy_ghcr.yml` → publica `:latest` + `:v<run_number>` a cada push
- **Credenciais da VPS:** em `docs/acessos_vps.md` (gitignored — NÃO commitar)

## Fluxo em 9 fases

### 1. Preparar commit local

```bash
# Trava credenciais fora do commit
git check-ignore docs/acessos_vps.md || (echo "PERIGO: credenciais não ignoradas"; exit 1)

git add -A
git diff --cached --name-only | grep -iE "acessos|vps" && { echo "FALHA: credenciais stageadas"; exit 1; }
```

Commit com mensagem estruturada (feat/fix + descrição).

**Pre-commit hooks**:
- ESLint exige i18n — adicionar keys em `app/javascript/dashboard/i18n/locale/{pt_BR,en}/captain.json`
- Rubocop metric violations: `# rubocop:disable Metrics/MethodLength,Metrics/AbcSize` antes da `class`

**Nunca usar `--no-verify`**.

### 2. Push + aguardar CI

```bash
git push origin <branch>
gh run list --repo rodribm10/iachat --branch <branch> --limit 1
# aguarda status "completed success" (~10-15min multi-arch)

# Pega número da tag gerada
gh run view --repo rodribm10/iachat <run_id> --log \
  | grep "imagetools create" -A 3 | grep -oE "v[0-9]+"
# → retorna "v67" (por exemplo)
```

**Sempre usar a tag `vN` específica, NUNCA `:latest`** (outras branches sobrescrevem).

### 3. Inspeção read-only da VPS

```bash
ssh root@76.13.174.155 '
docker stack ls
docker service inspect iachat_iachat_app --format "{{json .Spec}}" | python3 -m json.tool
docker service inspect iachat_iachat_app --format "{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}"
'
```

### 4. Gerar secrets únicos NA VPS

```bash
ssh root@76.13.174.155 "
mkdir -p /root/<stack-name>
cat > /root/<stack-name>/.secrets <<EOF
SECRET_KEY_BASE=\$(openssl rand -hex 64)
AR_PRIMARY=\$(openssl rand -hex 16)
AR_DETERMINISTIC=\$(openssl rand -hex 16)
AR_SALT=\$(openssl rand -hex 16)
POSTGRES_PASSWORD_NEW=\$(openssl rand -base64 24 | tr -d /=+)
EOF
chmod 600 /root/<stack-name>/.secrets
"
```

### 5. Criar `stack.yml` + `app.env` + `postgres_password.txt`

Templates em:
- `~/.claude/skills/chatwoot-staging-deploy/stack.yml.template`
- `~/.claude/skills/chatwoot-staging-deploy/app.env.template`

**Pontos críticos**:
- Traefik `rule=Host('<dns>')` com `priority=100` pra vencer catchall regex do prod
- Network pública `network_swarm_public` (external)
- Volumes isolados (`postgres_data`, `redis`, `storage`)
- Postgres password via Docker Secret (arquivo `/root/<stack>/postgres_password.txt`)
- `POSTGRES_DATABASE=iachat_staging` (não `production`)

### 6. Deploy

```bash
ssh root@76.13.174.155 "
docker pull ghcr.io/rodribm10/iachat:v<N>
docker stack deploy -c /root/<stack>/stack.yml --with-registry-auth <stack>
sleep 10
docker service ls --filter name=<stack>
"
```

Se `<stack>_app` reinicia em loop → é DB vazio. Próximo passo.

### 7. Schema + migrations (container one-off)

```bash
ssh root@76.13.174.155 "
docker run --rm --network <stack>_<stack>_internal \
  --env-file /root/<stack>/app.env \
  -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
  ghcr.io/rodribm10/iachat:v<N> \
  sh -c 'bundle exec rails db:schema:load db:migrate db:seed'
"
```

`DISABLE_DATABASE_ENVIRONMENT_CHECK=1` é necessário — Rails bloqueia destrutivas em prod, mas aqui DB é zero.

### 8. Restart do app

```bash
ssh root@76.13.174.155 "docker service update --force <stack>_app"
```

Aguarde ~20s. `docker service ps <stack>_app` deve mostrar `Running` sem crash.

### 9. Teste HTTPS

```bash
curl -sSI https://<dns>/
# Esperado: 302 redirect to /installation/onboarding
```

302 → abre no browser e cria admin via onboarding.

## Troubleshooting

| Sintoma | Fix |
|---|---|
| `installation_configs does not exist` | Falta Fase 7 (schema:load) |
| `ActiveRecord::ProtectedEnvironmentError` | Adicionar `DISABLE_DATABASE_ENVIRONMENT_CHECK=1` |
| Cert Let's Encrypt inválido | Labels Traefik erradas; conferir `priority=100` e `rule=Host()` não regex |
| 302 pra página do prod | Catchall ganhou; aumentar `priority` ou verificar `rule` específica |
| `image not found` no pull | Tag errada; `gh run list` pra confirmar |

## Segurança

1. `docs/acessos_vps.md` — gitignored. NUNCA commite.
2. Senha `Nicodemos1@@1` foi compartilhada no histórico — **trocar nas 4 VPSs** (Leo, Rodrigo, Financeiro, Oracle).
3. Secrets por stack — gerar novos, nunca reutilizar entre envs.
4. Tag `:latest` é sobrescrita por qualquer push — sempre usar `vN`.

## Estado atual de exemplo

Primeira execução desse runbook: **2026-04-21**
- Branch: `feat/captain-semantic-memory`
- Stack: `iachat-v2`
- DNS: `iachatv2.hoteis1001noites.com.br`
- Imagem: `ghcr.io/rodribm10/iachat:v67`
- Status: ✅ deploy bem-sucedido, aguardando onboarding do admin
