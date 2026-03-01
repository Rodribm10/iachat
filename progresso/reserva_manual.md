# Criação de Reservas Manuais

**Objetivo:**
Permitir que as recepcionistas possam criar reservas manualmente (bypassando o comportamento automático da IA), incluindo a associação direta a uma caixa de entrada (inbox) e um contato, além de preencher dados como check-in, check-out e status.

**Contexto:**
Antes, a rotina de criação de reservas ocorria exclusivamente de forma automatizada via `AiReservationMessageWorker` ou fluxos da IA. Havia necessidade de que, caso a IA não tenha executado a ação, a equipe pudesse criar a reserva pela própria UI.

**Passos:**
1. **Model & Endpoint (Backend):**
   - Confirmado que o model já possuía `inbox_id` (`belongs_to :inbox`).
   - Criamos o método `create` no `Api::V1::Accounts::Captain::ReservationsController` para suportar `POST`, que além de tudo garante a criação de um `ContactInbox` na caixa de entrada fornecida se o contato não existisse ainda no pool da referida caixa. (Método privado `create_params` validando inputs usando Strong Parameters).
   - Adicionamento de `post :create` no `config/routes.rb` para a rota namespace `captain/reservations`.

2. **Store & API (Frontend):**
   - No arquivo `captain/reservations.js` da API, introduzido método assíncrono genérico `.create(...)` postando ao endpoint.
   - Adicionado no *Vuex Store* (`dashboard/store/captain/reservations.js`) a action `create` que despacha a requisição e sinaliza mensagens de erro/sucesso.

3. **Componente de Modal & Tradução:**
   - Adicionada as labels de tradução JSON de Reservas em PT e EN (Ex: `CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL`).
   - Criado o arquivo `NewReservationModal.vue` usando componentes globais modulares (`Dialog`, `Input`, `ComboBox` e etc) e validando props de injeção direta de `inbox-id` e `contact-id`.

4. **Integração nas Telas (Views):**
   - **`Index.vue`** (Reservas em Lista Geral): Renderiza o subcomponente modal em overlay disparado pelo Header Button "Nova Reserva", onde recarrega as reservas (`fetchReservations(1)`) após inserção de sucesso.
   - **`ReservationSummary.vue`** (Painel lateral das conversas): Disponibilizado um novo botão que repassa diretamente os identificadores do Contato Atual e a Inbox Atual para que o formulário da Reserva seja gerado já pré-povoado e associado devidamente, exibido caso `!hasMarker`.

**Principais Códigos e Arquivos Alterados:**
- `app/javascript/dashboard/routes/dashboard/captain/reservations/components/NewReservationModal.vue`
- `app/javascript/dashboard/routes/dashboard/captain/reservations/Index.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/reservation/ReservationSummary.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`
- `enterprise/app/controllers/api/v1/accounts/captain/reservations_controller.rb`
- `config/routes.rb`
- Arquivos de tradução (pt_BR, en `captain.json`)
- `app/javascript/dashboard/store/captain/reservations.js`
- `app/javascript/dashboard/api/captain/reservations.js`

**Como validar ou reverter:**
1. **Validar:** Acessar a página global das IA Reservations ou o painel lateral de uma conversa e tocar em "Nova Reserva". Crie preenchendo as informações, e se aparecer as mensagens de confirmação sem console log error, a UI consumiu o Backend corretamente.
2. **Reverter:** Realizar um `$ git revert` desta feature ou dar Rollback / desfazer os commits. Nenhuma migração de database extra foi executada neste processo (portanto, safe revert).
