<script setup>
// Casca visual das páginas Sinal nativas: define as CSS variables do tema do
// Sinal escopadas a este container, respeitando o dark mode do Chatwoot
// (classe `dark` no body). O markup interno usa bg-[var(--surface)] etc.,
// idêntico ao do sinal-web.
</script>

<template>
  <div class="sinal-shell overflow-y-auto w-full h-full">
    <div class="max-w-[1400px] mx-auto px-4 sm:px-6 py-5">
      <slot />
    </div>
  </div>
</template>

<style lang="scss">
.sinal-shell {
  --bg: #f8f7f4;
  --surface: #ffffff;
  --surface-2: #f1f5f9;
  --surface-3: #e2e8f0;
  --border: #e2e8f0;
  --border-soft: #edeef2;
  --text: #0f172a;
  --muted: #64748b;
  --muted-2: #94a3b8;
  --accent: #2563eb;
  --accent-dim: #1d4ed8;
  --accent-glow: rgba(37, 99, 235, 0.12);
  --accent-soft: rgba(37, 99, 235, 0.08);
  --accent-border: rgba(37, 99, 235, 0.24);
  --accent-foreground: #ffffff;
  --ok: #16a34a;
  --warn: #d97706;
  --danger: #dc2626;
  --info: #2563eb;

  background: var(--bg);
  color: var(--text);
  letter-spacing: -0.011em;

  .font-display {
    font-family:
      'Inter',
      -apple-system,
      BlinkMacSystemFont,
      'Segoe UI',
      sans-serif;
  }
}

.dark .sinal-shell {
  --bg: #09090b;
  --surface: #121215;
  --surface-2: #18181b;
  --surface-3: #27272a;
  --border: #27272a;
  --border-soft: #1f1f23;
  --text: #f4f4f5;
  --muted: #a1a1aa;
  --muted-2: #71717a;
  --accent-glow: rgba(37, 99, 235, 0.25);
  --accent-soft: rgba(37, 99, 235, 0.16);
  --accent-border: rgba(37, 99, 235, 0.35);
  --ok: #4ade80;
  --warn: #fbbf24;
  --danger: #f87171;
  --info: #60a5fa;
}
</style>
