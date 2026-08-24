<script setup>
// "Adoção do sistema": quanto do atendimento humano passa pelo painel do
// Chatwoot vs. sai direto pelo WhatsApp do celular (fora do sistema) — split
// total e mapa de calor dia da semana x hora pra cruzar com a escala de
// plantão (o horário identifica quem está por trás, já que a resposta
// direta no WhatsApp não tem autor no banco).
import { computed } from 'vue';
import AdoptionHeatmap from './AdoptionHeatmap.vue';
import { formatNumber } from './helpers';

const props = defineProps({
  splitItems: {
    // [{ name, value, color }] — Pelo painel / Direto no WhatsApp
    type: Array,
    default: () => [],
  },
  heatmap: {
    // [{ dow, hour, panel, whatsapp_direct }] — 168 celulas (7 dias x 24h)
    type: Array,
    default: () => [],
  },
});

const total = computed(() =>
  props.splitItems.reduce((sum, item) => sum + item.value, 0)
);

const pct = value => {
  if (!total.value) return '0%';
  return `${Math.round((value / total.value) * 100)}%`;
};
</script>

<template>
  <div
    class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
  >
    <div>
      <h3 class="text-[15px] font-semibold text-[var(--text)]">
        {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.TITLE') }}
      </h3>
      <p class="mt-1 text-[12.5px] text-[var(--muted)]">
        {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.SUBTITLE') }}
      </p>
    </div>

    <div v-if="!total" class="py-8 text-center text-[var(--muted-2)] text-xs">
      {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.EMPTY') }}
    </div>
    <template v-else>
      <div class="mt-4 grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div
          v-for="item in splitItems"
          :key="item.name"
          class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface-2)] p-4"
        >
          <div class="flex items-center justify-between gap-2">
            <span
              class="inline-flex items-center gap-1.5 text-[12px] font-semibold text-[var(--muted)]"
            >
              <span
                class="h-[9px] w-[9px] rounded-full"
                :style="{ backgroundColor: item.color }"
              />
              {{ item.name }}
            </span>
            <span class="font-mono text-[11px] text-[var(--muted-2)]">
              {{
                $t('SINAL_REPORTS.SYSTEM_ADOPTION.REPLIES_COUNT', {
                  count: formatNumber(item.value),
                })
              }}
            </span>
          </div>
          <div
            class="mt-3 font-display text-[38px] font-semibold leading-none tracking-tight text-[var(--text)]"
          >
            {{ pct(item.value) }}
          </div>
          <div
            class="mt-3 h-[7px] overflow-hidden rounded-full bg-[var(--border-soft)]"
          >
            <div
              class="h-full rounded-full"
              :style="{ width: pct(item.value), backgroundColor: item.color }"
            />
          </div>
        </div>
      </div>

      <div
        class="mt-4 rounded-xl border border-[var(--border-soft)] bg-[var(--surface-2)] p-4"
      >
        <h4 class="text-[13px] font-semibold text-[var(--text)]">
          {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.HEATMAP_TITLE') }}
        </h4>
        <p class="mt-0.5 text-[11.5px] text-[var(--muted-2)]">
          {{ $t('SINAL_REPORTS.SYSTEM_ADOPTION.HEATMAP_SUBTITLE') }}
        </p>
        <div class="mt-3">
          <AdoptionHeatmap :cells="heatmap" />
        </div>
      </div>
    </template>
  </div>
</template>
