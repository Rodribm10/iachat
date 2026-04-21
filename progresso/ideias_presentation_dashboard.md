# Ideias: Dashboard Modo Apresentação

## Análise das Sugestões Anteriores

A sugestão do modelo "Keynote dentro do App" (Slides 16:9) com fundos pré-renderizados é excelente e muito aderente à filosofia de Design System e de Performance focada em "Aesthetics" para uma apresentação executiva.

**Por que a abordagem sugerida é superior a gerar imagens ao vivo (via API Nano Banana):**
1. **Latência e Confiabilidade:** Em uma apresentação ao vivo (projetor/TV), a última coisa que queremos é um fundo carregando lentamente ou uma API falhando, deixando a tela branca.
2. **Consistência Visual:** Gerar via IA ao vivo introduz imprevisibilidade ("alucinações" visuais). Para um relatório gerencial, o padrão visual transmite autoridade e seriedade. A consistência de ter "O fundo azul marinho do RH" todo mês constrói identidade de produto.
3. **Contraste (Acessibilidade)**: Em um fundo pré-gerado e testado pelo design (Brad Frost mode), sabemos exatamente que a fonte branca tamanho 64px vai ter leitura perfeita. Uma imagem gerada aleatoriamente pode ter manchas claras exatamente onde o número está, matando a legibilidade no projetor.

---

## Proposta de Arquitetura Visual (O "Como Fazer" no Vue/CSS)

Se formos implementar essa trilha "Keynote", aqui está como podemos estruturar o Front-end e o Design System para que a apresentação seja espetacular:

### 1. O Contêiner 16:9 Fixo (O "Palco")
Em vez de deixar o dashboard se expandir infinitamente em telas ultrawide (o que deforma os elementos), criamos um **container com aspect-ratio 16:9 fixo**.
- Ele escala proporcionalmente usando `transform: scale()` dependendo do tamanho do navegador (como o Canva faz no modo apresentação).
- Isso garante que o que você vê no seu Mac é **exatamente** o que vai aparecer no projetor. Sem quebras de linha surpresas.

### 2. A Camada de Fundo (Backgrounds Curados)
Vamos hospedar ~10 imagens de altíssima qualidade (WebP) na pasta `public/assets/presentation_bgs/`.
- `bg-hero-mensal.webp`
- `bg-gestao-ok.webp`
- `bg-gestao-critical.webp`
(Podemos sim usar o Midjourney ou Nano Banana *uma vez*, em ambiente de design, para gerar imagens abstratas belíssimas estilo *Dark Glassmorphism* ou *Fluid 3D shapes*, aprová-las, tratá-las com uma camada escura (`rgba(0,0,0,0.6)`) no Figma e salvar estaticamente).

No Vue, criamos um componente `<PresentationSlide>` que dinamicamente puxa esse fundo baseado no status ou tema do slide, usando `background-size: cover`.

### 3. Tipografia "Hero" (O Foco no Dado)
A tela atual tenta mostrar os detalhes das auditorias em texto corrido ("168 auditorias realizadas..."). Em projetor, isso é invisível.
A tipografia no modo apresentação precisará ser um componente separado com **escalas gigantes**:
- **Slide Title:** 48px a 64px (Ex: "Auditoria Express")
- **Big Number:** 120px a 160px (Ex: "70%")
- **Subtitle/Status:** 24px a 32px (Ex: "Abaixo da Meta")

### 4. Layout "Slide" - Anatomia Proposta
Um componente de Slide padrão teria:
1. **Top-left:** Logo miniatura + Tópico atual (Ex: 📊 Operação Geral)
2. **Center-Left:** O Número Gigante (O KPI) com uma seta de tendência (📈/📉).
3. **Right-side:** Um Ranking limpo (Top 3 melhores, Top 3 piores) usando Avatares grandes e barras de progresso grossas (pelo menos 16px de altura, com border-radius). Em vez de texto descrevendo a meta, apenas a barra colorida.
4. **Bottom:** Uma frase executiva de "Takeaway" ou o Insight gerado pela nossa IA atual ("Necessário focar em treinamento na unidade Prime VL").

### 5. Transições Cinematográficas
Como controlamos o Vue, podemos usar o `<Transition>` do Vue com animações CSS maravilhosas.
- Ao mudar do slide 1 para o 2, os números do KPI não apenas aparecem, eles sobem e entram em fade (`translateY` + `opacity`) com uma curva suave (cubic-bezier).
- Se tivermos barras de progresso, elas animam de 0% até o valor em 1 segundo. Isso traz o "feel premium" que a diretoria valoriza.

---

## O Veredito Tecnológico

A IA sugeriu o **"Modelo híbrido"** e organizar em uma "Biblioteca de assets (não gerar ao vivo)". **Eu concordo 100% com ela.**

Gerar imagem por API ao vivo para fundo de dashboard é over-engineering (engenhoca demais) e traz muito risco (custo, lentidão na tela, feiura aleatória) para pouco benefício. Investir 1 hora gerando os 10 fundos perfeitos e codar um layout fixo 16:9 fará o Chatwoot parecer uma ferramenta SaaS de $10.000/mês.

**Se você aprovar a direção do "Modelo Híbrido Keynote com Assets Fixos"**, os próximos passos reais seriam:
1. Criarmos um arquivo CSS específico para o Presentation Mode (tipografia gigante, cores absolutas para dark mode).
2. Criar o layout de roteador novo (`/dashboard/.../presentation`) e o componente de Slide que consome os dados do Dashboard mas cospe na tela nessa versão "Gigante e Limpa".
3. Exportar ou subir os fundos de imagem.

O que achou dos pontos mecânicos de CSS/Layout aplicados à ideia dela?
