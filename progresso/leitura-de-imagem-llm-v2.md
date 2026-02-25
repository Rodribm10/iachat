# Correção do Motor de Visão Computacional (Leitura de Imagens da IA) - V2

## O Problema
O AgentRunnerService foi ajustado para permitir envios multimodais à IA (OpenAI), no entanto, o usuário relatou que a IA passou a *alucinar* as imagens (informando ver "horário 00:00" em imagens perfeitamente formatadas).

## Causa Raiz Descoberta
Através de debugging do payload dentro dos scripts internos, descobrimos sucessivos problemas:
1. **Bloqueio de Download:** O Ngrok estava barrando o acesso à "image url" pela API da OpenAI. Resolvido enviando em Base64 Data URI nativamente no Payload.
2. **Coerção de Array em String (O Motivo da Cegueira da IA):** O payload em Base64 era uma `Array`. Contudo, ao passá-lo para a gem que orquestra os agentes (`ruby_llm`), foi descoberto que a biblioteca pegava nossa Array contendo o Base64 e convertia para formato "JSON String" antes de mandar pra OpenAI.
- Como chegava como Texto e não Objeto para o Servidor GPT, a Inteligência Artificial via um texto gigantesco incompreensível ao invés de uma "Imagem Analisável", levando a alucinações onde tentava apenas tirar conclusões da mensagem do usuário em si.

## Solução Implementada
Refatoramos o serviço `Captain::OpenAiMessageBuilderService`. Utilizando uma técnica presente no antigo projeto legado (`vision_service.rb`), nós mudamos a estrutura do envio.
- Antes: `[{type: 'image_url', image_url: {url: "https://ngrok.dev/rails/active_storage/..."}}]`
- Depois: `[{type: 'image_url', image_url: {url: "data:image/jpeg;base64,...CODIGO GIGANTE..."}}]`

Desta forma, os bytes reais da foto são lidos assincronamente pelo Rails (`file.blob.open`) e trafegados direto no pacote JSON do Payload do Agente.
- A IA passa a enxergar perfeitamente a imagem ignorando restrições de rede de ActiveStorage `disk` service ou bloqueios temporários de desenvolvimento (ngrok).

## Próximos Passos (Validação)
Você pode encaminhar a Imagem de Teste localmente lá em `http://localhost:3001` no Chatwoot (Widget Local) ou via Wuzapi para a conta do Bot. Como eu modifiquei algo sensível interno na class do Service, lembre que é essencial certificar-se que os jobs ou instâncias do Sidekiq tenham sofrido reload. (Basta derrubar o server `ctrl+C` e subir novamente com `make force_run`).
