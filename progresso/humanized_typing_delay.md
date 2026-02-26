# Melhorias no Delay Humanizado (Wuzapi/Captain)

**Objetivo:** Integrar o delay humanizado (leitura e digitação simuladas) com a configuração de atraso base controlada pelo front-end (`typing_delay` da Inbox), evitando atrasos excessivos e resolvendo uma *Race Condition* de mensagens concorrentes. Ocultar scripts temporários de teste da raiz do repositório.

**Contexto:**
- O delay fixo adicionado anteriormente bloqueava os testes e fugia do controle do administrador. Se o admin configurasse o delay no painel para "5", o sistema adicionava os passos humanizados de leitura e digitação *em cima* desses 5 segundos originais na fila do Sidekiq.
- Risco técnico (Race Condition): um `sleep(4)` para simulação de leitura permitia a chegada de uma nova mensagem, que ficaria ignorada ou atropelada.
- Sujeira no repositório: arquivos `.rb` na raiz do projeto poluindo o tracking do git.

**Passos:**
1. **Limpeza do Tracking:** Movidos os scripts descartáveis `test_wuzapi_parser.rb`, `test_wuzapi_service.rb`, `test_wuzapi_service2.rb` e `test_wuzapi_service3.rb` para `scripts/dev/`.
2. **Transferência do Delay Total:** Removemos o atraso cego na fila pelo Sidekiq (antes em `HookExecutionService` via `wait: delay.seconds`). O job engatilha agora imediatamente para a mensagem começar o fluxo visivelmente.
3. **Escalonamento do Delay Dinâmico:** Atualizado `ResponseBuilderJob` para usar `@inbox.typing_delay.to_i`. Agora, se `typing_delay` for maior que zero, ele é utilizado como *peso máximo* para a leitura e digitação, combinando a variação humana (jitter) mas respeitando a escala do front-end.
4. **Fechamento de Race Condition:** Adicionado novamente um check `return if debounce_requested?(message)` no final da pausa de "leitura", certificando que nenhuma mensagem invadiu nos segundos intermediários do `sleep`.

**Principais Códigos Alterados:**
- `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb`
- `enterprise/app/jobs/captain/conversation/response_builder_job.rb`

**Como Validar:**
No frontend, altere o valor de "Delay before responding" para um número baixo (ex: 2 segundos) e envie mensagens variadas no whatsapp. A resposta de leitura e digitação não vai exceder este tempo máximo. Depois aumente o número livremente. Teste enviar duas mensagens curtas em menos de 2 segundos para validar se a resposta não está atropelando o raciocínio.

**Como Reverter:**
As alterações em `HookExecutionService` podem ser revertidas readicionando `wait: delay.seconds` no `.set()` de enqueue do job. Em `ResponseBuilderJob`, as chamadas das lógicas de escala de delays com `.clamp(1.0, max...)` podem retornar ao padrão duro das branchs anteriores.
