# Objetivo
Melhorar o design e as conversões da Landing Page (`show.html.erb`), focando em interface moderna ("glassmorphism"), eliminação de scroll desnecessário, e implementação de gatilhos psicológicos de urgência (cronômetro).

# Contexto
A página antiga do iachat para atendimento de WhatsApp possuía um design simples. Como arquiteto e UX expert, a refatoração visual manteve a performance de um arquivo único (HTML/CSS inline leve) mas modernizou a apresentação utilizando as variáveis de cores dinâmicas para gerar maior apelo visual e Call-to-Action.

# Passos Realizados
1. Refatoração do layout com responsividade fluida via CSS `clamp()` para as fontes e paddings. O body passou a ter `overflow: hidden` na maioria das telas modernas para manter o formato "above-the-fold".
2. Aplicação de visual premium no card de contato usando `backdrop-filter: blur()`, reduzindo contraste chapado e gerando sensação de profundidade.
3. Adição de um Cronômetro regressivo ("Oferta expira em 10:00") que utiliza `sessionStorage` para manter a persistência entre recarregamentos de página.
4. Animação de "brilho" (shine) contínuo e pulso na sombra (`box-shadow`) do botão do WhatsApp para destacar de forma definitiva o CTA.

# Arquivos Alterados
- `app/views/public/landing_pages/show.html.erb`

# Variáveis / Features
- `countdownTimer`: Elemento e classe no JS nativo adicionado.
- `sessionKey = "lp_timer_"`: Controle por hostname para evitar resets de timer na mesma sessão.

# Como Validar
1. Abrir no navegador a URL de teste local de algum Landing Host (/lp/[hostname]).
2. Testar o redimensionamento de janela; o layout não deve forçar scroll a não ser que a altura seja criticamente pequena (ex: < 500px).
3. Aguardar os 10 minutos (ou editar session storage) para validar a cor vermelha piscante do cronômetro finalizado.

# Como Reverter
Executar no terminal raiz: `git checkout app/views/public/landing_pages/show.html.erb` caso ainda não tenha "commitado", ou usar o git revert correspondente.
