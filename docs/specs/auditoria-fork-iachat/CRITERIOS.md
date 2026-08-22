# CRITÉRIOS DE ACEITAÇÃO

Nada é "pronto" no olho. Pronto = todos os itens da fase verificados, um a um.
Falhou um → volta ao passo do `PLANO.md` que o cobre, corrige, re-verifica.

## Critérios globais (valem em toda fase)

- [ ] `bundle exec rspec` verde
- [ ] `pnpm test` verde
- [ ] `bundle exec rubocop` sem ofensa nova
- [ ] `pnpm run eslint` sem erro novo
- [ ] Deploy em staging feito e conversa real de ponta a ponta funcionando (cliente manda
      mensagem no WhatsApp → Hermes responde → mensagem chega)
- [ ] Nenhum job novo no DeadSet do Sidekiq depois de 24h em staging

---

## F0 — Triagem

- [ ] As 10 consultas rodadas em produção, com o resultado colado no `RELATORIO.md`
- [ ] Cada um dos 10 subsistemas com destino escrito: VIVO, MORTO INÚTIL ou PARADO MAS ÚTIL
- [ ] Cada destino acompanhado do número que o sustenta (não "acho que não usa" — "0 draws em 90 dias")
- [ ] Contagem de linhas das 16 tabelas órfãs registrada
- [ ] Lista final de F1 (o que sai) e de F4 (o que reativa) fechada e aprovada por você
- [ ] Onde meu palpite prévio da auditoria errou está marcado explicitamente

## F1 — Remoção

- [ ] `grep -ri jasmine app/ enterprise/ lib/ config/` → zero ocorrência
- [ ] Cada classe da lista F1.2 não existe mais e nada quebra: `bundle exec rails zeitwerk:check` passa
- [ ] Migration de drop roda e reverte (`db:migrate` → `db:rollback` → `db:migrate` sem erro)
- [ ] Tabela com linha em produção foi exportada pra CSV **antes** do drop, ou confirmada vazia
- [ ] `.env.example` sem as 11 variáveis de tooling; app sobe com o `.env.example` como referência
- [ ] `Reports::ExecutiveController` continua respondendo (não foi removido por engano)
- [ ] `Captain::Tools::*` continua intacta (sai só em F3)
- [ ] Dashboard carrega sem erro de console

## F2 — Módulos por projeto

- [ ] `accounts.feature_flags_ext_1` existe e `Featurable` mapeia as duas colunas
- [ ] As 12 features aparecem na tela do Super Admin (`/super_admin/accounts/:id`) com caixinha
- [ ] Conta nova nasce com **todas** as 12 desligadas
- [ ] Ligar/desligar pelo Super Admin surte efeito sem restart
- [ ] `tools/list` do MCP para a inbox da academia **não** contém `check_suite_availability`,
      `send_suite_images`, `reschedule_reservation`, `mark_reservation_pending`
- [ ] `tools/list` para a inbox de hotel continua com as 19 tools de hoje
- [ ] Cron de módulo desligado não enfileira job pra aquela conta (verificar no Sidekiq)
- [ ] Rota de módulo desligado devolve 404, não 500
- [ ] Menu do dashboard da academia não mostra Reservas, Roleta nem Galeria
- [ ] Migration de dados rodou: **nenhuma** conta de hotel perdeu funcionalidade que tinha antes
- [ ] `spec/models/concerns/featurable_spec.rb` cobrindo o limite de 63 por coluna

## F3 — Desligar o Captain interno

**Portão de entrada:** F0.1 devolveu zero assistants com `engine='captain_interno'`.
Se não, F3 não começa.

### F3.1 — Guardas (obrigatório antes de F3.2)
- [ ] `SYSTEM_PROMPT_LEAK_PATTERNS` e `THOUGHT_LEAK_PATTERNS` aplicados no callback do Hermes
- [ ] Spec: resposta começando com `[Contexto]` → não vira mensagem ao cliente
- [ ] Spec: resposta contendo `handoff_to_` → não vira mensagem ao cliente
- [ ] Spec: resposta contendo `{{ variavel }}` (Liquid cru) → não vira mensagem ao cliente
- [ ] Spec: resposta contendo JSON cru → não vira mensagem ao cliente
- [ ] Em todos os casos: nota privada criada **e** conversa marcada como triagem humana
- [ ] `ERROR_PAYLOAD_PATTERNS` continua funcionando (não houve regressão do fix de 25/07)

### F3.2/F3.3 — Remoção
- [ ] Arquivos da lista removidos; `rails zeitwerk:check` passa
- [ ] `Captain::Tools::GeneratePixTool` intacta e o fluxo da landing page gera PIX
- [ ] `captain/tools/copilot/*` intacta
- [ ] Cron `captain_codex_refresh_tokens_job` fora do `schedule.yml`
- [ ] `HookExecutionService` sem bifurcação: toda inbox com assistant vai pro Hermes
- [ ] `CAPTAIN_HERMES_INBOX_IDS` e as env vars legacy fora do código e do `.env.example`
- [ ] 48h em produção sem aumento de conversa em triagem humana em relação à semana anterior

## F4 — Reativações

Um bloco por item que F0 classificar como PARADO MAS ÚTIL. Mínimo:

- [ ] O item está atrás da feature correspondente criada em F2
- [ ] Existe um caminho de verificação que prova que ele produz efeito
      (ex.: "CEO Digest chegou no Mattermost na segunda", "lembrete disparou pro contato de teste")
- [ ] Está documentado no `RELATORIO.md` o que estava quebrado e o que consertou
- [ ] O heartbeat de cron cobre o job reativado

## F5 — Sync com upstream

- [ ] Catálogo de conflitos levantado e decidido item a item **antes** do primeiro merge
- [ ] Cada bloco de merge fecha com a suíte verde
- [ ] `VERSION_CW` = 4.17.0
- [ ] Staging rodando com atendimento real por 48h antes de prod
- [ ] Nenhuma feature do fork perdida no merge — checklist das 12 features de F2 revalidado
- [ ] Migrations do upstream aplicadas sem perda de dado das tabelas do fork
- [ ] Plano de rollback escrito (imagem anterior + `db:rollback` até onde) antes do deploy em prod
