<script setup>
import DonutChart from './DonutChart.vue';
import { formatNumber } from './helpers';

const props = defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  items: { type: Array, default: () => [] },
  unit: { type: String, default: '' },
});

const pct = value => {
  const total = props.items.reduce((sum, item) => sum + item.value, 0);
  if (!total) return '0%';
  return `${Math.round((value / total) * 100)}%`;
};
</script>

<template>
  <div
    class="min-w-0 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-5 flex flex-col"
  >
    <h3 class="text-[14px] font-semibold text-[var(--text)]">{{ title }}</h3>
    <p
      class="mt-1.5 min-h-[36px] text-[12px] leading-[1.5] text-[var(--muted)]"
    >
      {{ description }}
    </p>
    <DonutChart :items="items" :unit="unit" :size="196" />
    <div
      class="min-h-[37px] flex flex-wrap justify-center gap-x-3 gap-y-1 text-[11px] text-[var(--muted)]"
    >
      <span
        v-for="item in items"
        :key="item.name"
        class="inline-flex items-center gap-1.5"
      >
        <span
          class="h-2 w-2 rounded-full"
          :style="{ backgroundColor: item.color }"
        />
        {{ `${item.name} ${formatNumber(item.value)} · ${pct(item.value)}` }}
      </span>
    </div>
    <div
      class="mt-3.5 pt-3 border-t border-[var(--border-soft)] text-[12.5px] leading-[1.45] text-[var(--muted)]"
    >
      <slot name="footer" />
    </div>
  </div>
</template>
