<script setup>
// Réplica em SVG puro do AreaChart (recharts) do overview do Sinal:
// série atual em área com gradiente, série anterior em linha tracejada.
import { computed, ref } from 'vue';
import { fmtDay, formatNumber } from './helpers';

const props = defineProps({
  series: {
    // [{ day: 'YYYY-MM-DD', current: Number, previous: Number }]
    type: Array,
    default: () => [],
  },
  height: { type: Number, default: 220 },
});

const WIDTH = 1000;
const PAD_X = 8;
const PAD_TOP = 12;
const PAD_BOTTOM = 24;

const hovered = ref(null);

const maxValue = computed(() =>
  Math.max(1, ...props.series.flatMap(p => [p.current, p.previous]))
);

const xFor = index => {
  const count = Math.max(1, props.series.length - 1);
  return PAD_X + (index * (WIDTH - PAD_X * 2)) / count;
};

const yFor = value =>
  PAD_TOP +
  (1 - value / maxValue.value) * (props.height - PAD_TOP - PAD_BOTTOM);

const linePath = key =>
  props.series
    .map(
      (p, i) =>
        `${i === 0 ? 'M' : 'L'}${xFor(i).toFixed(1)},${yFor(p[key]).toFixed(1)}`
    )
    .join(' ');

const areaPath = computed(() => {
  if (!props.series.length) return '';
  const base = props.height - PAD_BOTTOM;
  return `${linePath('current')} L${xFor(props.series.length - 1).toFixed(1)},${base} L${xFor(0).toFixed(1)},${base} Z`;
});

const tickIndexes = computed(() => {
  const count = props.series.length;
  if (count <= 8) return props.series.map((_, i) => i);
  const step = Math.ceil(count / 8);
  return props.series.map((_, i) => i).filter(i => i % step === 0);
});

const tooltipStyle = computed(() => {
  if (hovered.value === null) return {};
  const pct = (xFor(hovered.value) / WIDTH) * 100;
  return {
    left: `${Math.min(86, Math.max(4, pct))}%`,
  };
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
      <defs>
        <linearGradient id="sinal-current-grad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="5%" stop-color="var(--accent)" stop-opacity="0.35" />
          <stop offset="95%" stop-color="var(--accent)" stop-opacity="0" />
        </linearGradient>
      </defs>
      <path
        v-if="series.length"
        :d="areaPath"
        fill="url(#sinal-current-grad)"
        stroke="none"
      />
      <path
        v-if="series.length"
        :d="linePath('previous')"
        fill="none"
        stroke="var(--muted-2)"
        stroke-width="1.5"
        stroke-dasharray="4 4"
        vector-effect="non-scaling-stroke"
      />
      <path
        v-if="series.length"
        :d="linePath('current')"
        fill="none"
        stroke="var(--accent)"
        stroke-width="2.5"
        vector-effect="non-scaling-stroke"
      />
      <g v-for="(point, index) in series" :key="point.day">
        <rect
          :x="xFor(index) - WIDTH / Math.max(2, series.length * 2)"
          y="0"
          :width="WIDTH / Math.max(1, series.length)"
          :height="height"
          fill="transparent"
          @mouseenter="hovered = index"
        />
        <circle
          v-if="hovered === index"
          :cx="xFor(index)"
          :cy="yFor(point.current)"
          r="4"
          fill="var(--accent)"
        />
      </g>
    </svg>
    <div
      class="absolute bottom-0 inset-x-2 flex justify-between font-mono text-[10px] text-[var(--muted-2)] pointer-events-none"
    >
      <span v-for="index in tickIndexes" :key="index">
        {{ fmtDay(series[index].day) }}
      </span>
    </div>
    <div
      v-if="hovered !== null && series[hovered]"
      class="absolute top-2 z-10 rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-3 text-xs shadow-xl pointer-events-none"
      :style="tooltipStyle"
    >
      <div
        class="font-semibold text-[var(--text)] mb-1.5 border-b border-[var(--border-soft)] pb-1"
      >
        {{ fmtDay(series[hovered].day, true) }}
      </div>
      <div
        class="flex items-center justify-between gap-3 text-[var(--accent)] font-semibold"
      >
        <span class="flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full bg-[var(--accent)]" />
          {{ $t('SINAL_REPORTS.CHART.CURRENT') }}
        </span>
        <span class="font-mono">{{
          formatNumber(series[hovered].current)
        }}</span>
      </div>
      <div
        class="flex items-center justify-between gap-3 text-[var(--muted)] mt-1"
      >
        <span class="flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full bg-[var(--muted-2)]" />
          {{ $t('SINAL_REPORTS.CHART.PREVIOUS') }}
        </span>
        <span class="font-mono">{{
          formatNumber(series[hovered].previous)
        }}</span>
      </div>
    </div>
  </div>
</template>
