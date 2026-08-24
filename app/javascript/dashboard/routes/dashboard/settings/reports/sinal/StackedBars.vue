<script setup>
// Barras empilhadas em SVG puro (réplica do BarChart empilhado da página
// Mídia do Sinal). `buckets` = [{ label, values: { tipo: n } }],
// `types` = [{ key, label, color }] na ordem de empilhamento.
import { computed, ref } from 'vue';
import { formatNumber } from './helpers';

const props = defineProps({
  buckets: { type: Array, default: () => [] },
  types: { type: Array, default: () => [] },
  height: { type: Number, default: 280 },
});

const WIDTH = 1000;
const PAD_TOP = 8;
const PAD_BOTTOM = 24;

const hovered = ref(null);

const totalFor = bucket =>
  props.types.reduce((sum, t) => sum + (bucket.values[t.key] || 0), 0);

const maxTotal = computed(() => Math.max(1, ...props.buckets.map(totalFor)));

const barWidth = computed(() =>
  Math.min(48, (WIDTH / Math.max(1, props.buckets.length)) * 0.62)
);

const slotWidth = computed(() => WIDTH / Math.max(1, props.buckets.length));

const segmentsFor = (bucket, index) => {
  const usable = props.height - PAD_TOP - PAD_BOTTOM;
  const x = index * slotWidth.value + (slotWidth.value - barWidth.value) / 2;
  let yCursor = props.height - PAD_BOTTOM;
  const segments = [];
  props.types.forEach(type => {
    const value = bucket.values[type.key] || 0;
    if (!value) return;
    const h = (value / maxTotal.value) * usable;
    yCursor -= h;
    segments.push({ key: type.key, color: type.color, x, y: yCursor, h });
  });
  return segments;
};

const tickIndexes = computed(() => {
  const count = props.buckets.length;
  if (count <= 10) return props.buckets.map((_, i) => i);
  const step = Math.ceil(count / 10);
  return props.buckets.map((_, i) => i).filter(i => i % step === 0);
});

const tooltipStyle = computed(() => {
  if (hovered.value === null) return {};
  const pct =
    ((hovered.value * slotWidth.value + slotWidth.value / 2) / WIDTH) * 100;
  return { left: `${Math.min(80, Math.max(4, pct))}%` };
});

const hoveredRows = computed(() => {
  if (hovered.value === null) return [];
  const bucket = props.buckets[hovered.value];
  return [...props.types]
    .reverse()
    .map(type => ({ ...type, value: bucket.values[type.key] || 0 }))
    .filter(row => row.value > 0);
});
</script>

<template>
  <div class="relative w-full" :style="{ height: `${height}px` }">
    <svg
      class="w-full h-full"
      :viewBox="`0 0 ${WIDTH} ${height}`"
      preserveAspectRatio="none"
      @mouseleave="hovered = null"
    >
      <line
        v-for="frac in [0.25, 0.5, 0.75]"
        :key="frac"
        x1="0"
        :x2="WIDTH"
        :y1="PAD_TOP + frac * (height - PAD_TOP - PAD_BOTTOM)"
        :y2="PAD_TOP + frac * (height - PAD_TOP - PAD_BOTTOM)"
        stroke="var(--border-soft)"
        stroke-width="1"
        vector-effect="non-scaling-stroke"
      />
      <g v-for="(bucket, index) in buckets" :key="bucket.label">
        <rect
          :x="index * slotWidth"
          y="0"
          :width="slotWidth"
          :height="height"
          fill="transparent"
          @mouseenter="hovered = index"
        />
        <rect
          v-for="segment in segmentsFor(bucket, index)"
          :key="segment.key"
          :x="segment.x"
          :y="segment.y"
          :width="barWidth"
          :height="segment.h"
          :fill="segment.color"
          :opacity="hovered === null || hovered === index ? 1 : 0.45"
          rx="2"
        />
      </g>
    </svg>
    <div
      class="absolute bottom-0 inset-x-0 flex justify-between px-1 font-mono text-[10px] text-[var(--muted-2)] pointer-events-none"
    >
      <span v-for="index in tickIndexes" :key="index">
        {{ buckets[index].label }}
      </span>
    </div>
    <div
      v-if="hovered !== null && buckets[hovered]"
      class="absolute top-2 z-10 rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-3 text-xs shadow-xl pointer-events-none min-w-[150px]"
      :style="tooltipStyle"
    >
      <div
        class="font-semibold text-[var(--text)] mb-1.5 border-b border-[var(--border-soft)] pb-1"
      >
        {{ buckets[hovered].label }}
      </div>
      <div
        v-for="row in hoveredRows"
        :key="row.key"
        class="flex items-center justify-between gap-3 mt-1"
      >
        <span class="flex items-center gap-1.5 text-[var(--muted)]">
          <span
            class="w-2 h-2 rounded-sm"
            :style="{ backgroundColor: row.color }"
          />
          {{ row.label }}
        </span>
        <span class="font-mono text-[var(--text)]">{{
          formatNumber(row.value)
        }}</span>
      </div>
      <div
        class="flex items-center justify-between gap-3 mt-1.5 pt-1 border-t border-[var(--border-soft)] font-semibold"
      >
        <span class="text-[var(--muted)]">{{ $t('SINAL_REPORTS.TOTAL') }}</span>
        <span class="font-mono text-[var(--text)]">{{
          formatNumber(totalFor(buckets[hovered]))
        }}</span>
      </div>
    </div>
  </div>
</template>
