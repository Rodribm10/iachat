# Solução: Debounce Dinâmico + Trava de Concorrência da IA

## Objetivo
Resolver chamadas duplicadas para o LLM e estabilizar o agrupamento de mensagens (debounce) não-bloqueante na geração de respostas da IA.

## Contexto
O Chatwoot apresentava falhas de agrupamento quando as mensagens chegavam muito perto do final do debounce. O uso do `sleep 10s` direto no Worker amarrava as threads do sistema. E quando uma "condição de corrida" acontecia (uma MSG2 enviava o Job enquanto a MSG1 já estava conectada no OpenAI), o sistema gerava 2 respostas para a mesma conversa.

## Passos Implementados

1. **Agendamento no Sidekiq (Debounce Dinâmico)**
   - Removemos o `sleep(10)` da Thread.
   - Usamos o `perform_later(wait: X)` dentro do `HookExecutionService.schedule_captain_response`.
   - Se uma MSG2 cai segundos depois, ela agenda o Job *mais para a frente*. Quando o Job1 acorda no passado, o método `debounce_requested?` nota que não é a mais recente e **aborta** (Early Return), delegando a responsabilidade para a MSG2 agendada.

2. **Trava Distribuída (Mutex via `Rails.cache`)**
   - Injetamos um "Cadeado" atômico que só permite a IA responder a uma conversa por vez.
   - Antes de iniciar a digitação no Chat/WhatsApp e chamar o OpenAI, o Job trava a chave `captain_response_lock_ID` por `60.seconds`.
   - Se outro Job (como o da MSG2) passar pelo relógio enquanto a primeira requisição anda na rede, ele baterá na trava e descartará rodar a IA 2 vezes, garantindo segurança de processamento.
   - O `ensure` no final apaga a trava obrigatoriamente independente do desfecho do código.

## Principais Arquivos Alterados

- `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb`
- `enterprise/app/jobs/captain/conversation/response_builder_job.rb`

## Callbacks ou APIs Utilizadas
- `Rails.cache.write(unless_exist: true)`: Cache atômico que serve de Mutex.
- `Sidekiq::Worker.set(wait: X)`: ActiveJob Delay Queue.

## Como Validar
Enviar N mensagens em uma mesma conversa pelo Whatsapp/Inbox em um curto período (Ex: Oi / Tudo bem? / Quanto custa?) dentro da janela de `typing_delay` de 10 segundos.
Apenas UMA requisição (a mais demorada) processará a IA após 10 segundos agrupando todo o histórico de uma vez, mantendo uma única e coesa mensagem final.

## Como Reverter
- No `response_builder_job.rb`, remover o bloco envolto com `lock_key = "captain_response_loc..."` re-adicionando `sleep` hardcoded.
- E no `HookExecutionService` voltar a usar o `.perform_later` direto (sem `.set(wait)`).
