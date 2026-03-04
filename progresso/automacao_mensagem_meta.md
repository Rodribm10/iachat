# Resolução: Automação por Conteúdo da Mensagem (Meta Ads)

**Objetivo:** Criar uma regra de automação no Chatwoot que aplica uma etiqueta automaticamente quando uma mensagem específica (geralmente vinda de um link do Meta Ads/WhatsApp) é recebida.

**Contexto e Desafios Encontrados:**
1. **Tradução e Disponibilidade:** Em Português, a condição "Message Content" é traduzida como **"Mensagem contém"**. Porém, ela só aparece se o evento selecionado for **"Mensagem Criada"** (Message Created), e não "Conversa Criada".
2. **Separação por Vírgulas (Bug Silencioso):** O Chatwoot usa o tipo de input `comma_separated_plain_text` para o campo "Mensagem contém". Isso significa que se a frase da campanha contiver uma vírgula (ex: *"Olá, tenho interesse"*), o sistema divide a frase em duas strings distintas e exige que a mensagem recebida seja exatamente igual a uma delas, fazendo com que a automação falhe.

**Passos para a Resolução:**
1. Criar a Automação e definir o **Evento** como **Mensagem Criada**.
2. Na seção de Condições, escolher **Mensagem contém**.
3. Mudar o operador de "Igual a" para **"Contém"**.
4. No campo de valor, inserir a frase do anúncio **removendo a vírgula** ou colando apenas o trecho antes da vírgula (Ex: `Olá! Tenho interesse e queria mais informações`).
5. Nas Ações, definir **Adicionar Rótulo** e escolher a tag desejada da campanha.

**Principais Códigos/Arquivos Analisados (Backend/Frontend):**
- `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`: Onde a condição `content` é mapeada no evento de `message_created`.
- `app/javascript/dashboard/composables/useEditableAutomation.js`: Onde o input `comma_separated_plain_text` é convertido para envio (responsável pelo problema da quebra no texto por vírgulas).
- `app/services/automation_rules/conditions_filter_service.rb` e `app/services/filter_service.rb`: Serviços que processam e validam as condições da automação (a busca é feita no campo banco de dados através da sintaxe `LOWER(messages.processed_message_content)`).

**Como validar ou reverter:**
- **Validar:** Simular o envio de uma nova mensagem no WhatsApp usando o mesmo formato definido na campanha (antes ou após a vírgula). O painel do Chatwoot deve aplicar o rótulo da campanha de forma simultânea à recepção da mensagem.
- **Reverter:** Pausar a regra no painel em `Configurações > Automação` alternando a chave de 'Ativo', ou excluí-la permanentemente.
