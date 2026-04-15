# Reserva 1001 — Fase 5: Polish visual

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development

**Goal:** Transformar a página pública num produto premium com animações, carrossel, skeletons e micro-interações. A base funcional está toda pronta (fases 1-4); esta fase é exclusivamente sobre percepção de qualidade.

**Tech stack adicional:** framer-motion (já instalado) · animejs (já instalado) · canvas-confetti (instalar) · embla-carousel-react (instalar — pro carrossel de fotos)

**Spec:** `docs/superpowers/specs/2026-04-13-reserva-1001-design.md` seção 10
**Fases anteriores:** 1, 2, 3, 3.5, 4 completas

---

## Escopo

### ✅ Entra nesta fase

1. **Hero section** no topo da página pública com reveal escalonado (framer-motion)
2. **Carrossel de fotos** substitui o grid atual — com swipe, indicadores, lightbox em tela cheia
3. **Stagger entrance** nas opções de categoria/unidade quando muda a marca (framer-motion `staggerChildren`)
4. **Price pulse** — animação de escala quando o preço recalcula (anime.js)
5. **QR code glow** — borda animada pulsando na tela de checkout (CSS + motion)
6. **Skeleton screens** em vez de spinners no form e galeria
7. **SuccessScreen upgrade** — confetti + check SVG desenhado com anime.js
8. **Micro-interactions** em botões (hover scale, subtle glow)
9. **AnimatePresence** pras transições entre etapas (form → checkout → success)

### ❌ Fora de escopo

- Mudanças de layout (ex: hero "parallax" com scroll) — só reveal
- Mudança de fontes/cores (é editável no admin)
- Mexer em lógica de negócio

---

## Tasks

### Task 1: Hero section com reveal

**Files:**
- Create: `src/components/reservation/HeroSection.tsx`
- Modify: `src/pages/ReservationPage.tsx` (usa HeroSection no topo)

Cria um hero mais impactante: stagger entrance dos elementos (subtítulo → título → tagline) com `motion.div` e `variants`. Timeline: 0ms subtítulo, 200ms título, 400ms tagline.

### Task 2: Carrossel de fotos com lightbox

**Files:**
- Install: `pnpm add embla-carousel-react`
- Modify: `src/components/reservation/ImageGallery.tsx` (substitui grid por carrossel)

Swipe horizontal, dots indicadores, autoplay 4s (pausa no hover). Click numa foto abre lightbox em tela cheia (overlay escuro + `<img>` centralizado + botão X + ←/→ pra navegar + ESC pra fechar).

### Task 3: Stagger entrance nos selects de categoria/unidade

**Files:**
- Modify: `src/components/reservation/StayDetailsStep.tsx`

Quando a marca muda e as unidades/categorias re-renderizam, cada `<option>` (ou melhor, cada card visual de opção se virar custom dropdown) aparece com delay escalonado. Usar `AnimatePresence` + `motion.li` com `initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}` e delay por índice.

Como o HTML `<select>` não anima filhos, vou fazer um **chip group** por baixo do select mostrando as opções selecionáveis com hover state animado. O select mantido pra acessibilidade.

### Task 4: Price pulse quando recalcula

**Files:**
- Modify: `src/components/reservation/PriceSummary.tsx`

`useEffect` que dispara `anime({ targets: ref.current, scale: [1, 1.08, 1], duration: 400 })` toda vez que `totalCents` muda. Ref no `<div>` principal.

### Task 5: QR code glow animation

**Files:**
- Modify: `src/components/checkout/PixCheckout.tsx`

Animação CSS infinita na borda do container do QR code: `@keyframes` alternando `box-shadow` entre `0 0 30px rgba(201,169,97,0.4)` e `0 0 60px rgba(201,169,97,0.7)`. Usar via classe ou `motion.div` com `animate={{ boxShadow: [...] }}` loop.

### Task 6: Skeleton screens

**Files:**
- Create: `src/components/ui/skeleton.tsx`
- Modify: `src/components/reservation/StayDetailsStep.tsx`, `ImageGallery.tsx`, `PriceSummary.tsx` (mostram skeleton quando dados estão carregando)

Skeleton reutilizável com shimmer animado (CSS keyframes). Cada componente que hoje mostra "Carregando..." ganha um skeleton com o formato do conteúdo final.

### Task 7: SuccessScreen upgrade

**Files:**
- Install: `pnpm add canvas-confetti @types/canvas-confetti`
- Modify: `src/components/checkout/SuccessScreen.tsx`

- Confetti burst com cores da paleta do tenant (champagne + rose-gold + emerald)
- Check SVG desenhado com anime.js (`stroke-dashoffset` 0 → 1)
- Texto com reveal escalonado

### Task 8: Micro-interactions em botões

**Files:**
- Modify: `src/components/ui/button.tsx`

Adiciona `hover:scale-[1.02]` ao primary/secondary (já tem), e subtle `hover:glow-champagne` animado. Adiciona `active:scale-[0.98]` pra tactile feedback.

### Task 9: AnimatePresence entre fases do ReservationFlow

**Files:**
- Modify: `src/components/reservation/ReservationFlow.tsx`

Envolve o conteúdo de cada fase (form/checkout/success) com `<AnimatePresence mode="wait">` e `<motion.div key={phase} initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: -20 }} />` — slide + fade suave na transição.

---

## Validação

Ao final, tudo deve continuar passando:
```bash
pnpm typecheck
pnpm lint
pnpm test
pnpm build
```

Testes existentes continuam no verde. Novos testes não são obrigatórios (polish visual é difícil de testar automaticamente — QA visual manual).

## Critério de conclusão

- [ ] Hero aparece com stagger no boot
- [ ] Fotos viram carrossel swipable + lightbox
- [ ] Selecionar uma nova marca faz as opções "entrarem" em escalado
- [ ] Preço pulsa quando recalcula
- [ ] QR code tem glow pulsante
- [ ] Skeletons aparecem no lugar de "Carregando..."
- [ ] Tela de sucesso com confetti + check animado
- [ ] Transições entre etapas com slide suave
- [ ] Build < 700 KB (meta de não estourar com as libs novas)
