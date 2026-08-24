<script setup>
// "Visão mensal": barras agrupadas (respostas da IA × humanas) + linha de
// recebidas, em SVG puro — réplica do ComposedChart da branch do Sinal.
import { computed, ref } from 'vue';
import { formatMonthLabel, formatNumber } from './helpers';

const props = defineProps({
  months: {
    // [{ month: 'YYYY-MM', received, ai, human }]
    type: Array,
    default: () => [],
  },
  height: { type: Number, default: 250 },
});

const WIDTH = 1000;
const PAD_TOP = 10;
const PAD_BOTTOM = 26;

const hovered = ref(null);

const maxValue = computed(() =>
  Math.max(1, ...props.months.flatMap(m => [m.received, m.ai, m.human]))
);

const slotWidth = computed(() => WIDTH / Math.max(1, props.months.length));
const barWidth = computed(() => Math.min(46, slotWidth.value * 0.28));

const yFor = value =>
  PAD_TOP +
  (1 - value / maxValue.value) * (props.height - PAD_TOP - PAD_BOTTOM);

const barsFor = (month, index) => {
  const center = index * slotWidth.value + slotWidth.value / 2;
  const base = props.height - PAD_BOTTOM;
  return [
    {
      key: 'ai',
      color: 'var(--accent)',
      x: center - barWidth.value - 2,
      value: month.ai,
    },
    { key: 'human', color: '#FBBF24', x: center + 2, value: month.human },
  ].map(bar => ({
    ...bar,
    y: yFor(bar.value),
    h: Math.max(0, base - yFor(bar.value)),
  }));
};

const linePath = computed(() =>
  props.months
    .map((month, index) => {
      const x = index * slotWidth.value + slotWidth.value / 2;
      return `${index === 0 ? 'M' : 'L'}${x.toFixed(1)},${yFor(month.received).toFixed(1)}`;
    })
    .join(' ')
);

const tooltipStyle = computed(() => {
  if (hovered.value === null) return {};
  const pct =
    ((hovered.value * slotWidth.value + slotWidth.value / 2) / WIDTH) * 100;
  return { left: `${Math.min(78, Math.max(4, pct))}%` };
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
      <g v-for="(month, index) in months" :key="month.month">
        <rect
          :x="index * slotWidth"
          y="0"
          :width="slotWidth"
          :height="height"
          fill="transparent"
          @mouseenter="hovered = index"
        />
        <rect
          v-for="bar in barsFor(month, index)"
          :key="bar.key"
          :x="bar.x"
          :y="bar.y"
          :width="barWidth"
          :height="bar.h"
          :fill="bar.color"
          :opacity="hovered === null || hovered === index ? 1 : 0.45"
          rx="4"
        />
      </g>
      <path
        v-if="months.length > 1"
        :d="linePath"
        fill="none"
        stroke="var(--muted)"
        stroke-width="2"
        stroke-dasharray="5 4"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    <div
      class="absolute bottom-0 inset-x-0 flex justify-around font-mono text-[10px] text-[var(--muted-2)] pointer-events-none"
    >
      <span v-for="month in months" :key="month.month">
        {{ formatMonthLabel(month.month) }}
      </span>
    </div>
    <div
      v-if="hovered !== null && months[hovered]"
      class="absolute top-2 z-10 rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-3 text-xs shadow-xl pointer-events-none min-w-[170px]"
      :style="tooltipStyle"
    >
      <div
        class="font-semibold text-[var(--text)] mb-1.5 border-b border-[var(--border-soft)] pb-1"
      >
        {{ formatMonthLabel(months[hovered].month) }}
      </div>
      <div class="flex items-center justify-between gap-3 mt-1">
        <span class="flex items-center gap-1.5 text-[var(--muted)]">
          <span class="w-2 h-2 rounded-full bg-[var(--accent)]" />
          {{ $t('SINAL_REPORTS.MONTHLY.AI') }}
        </span>
        <span class="font-mono text-[var(--text)]">{{
          formatNumber(months[hovered].ai)
        }}</span>
      </div>
      <div class="flex items-center justify-between gap-3 mt-1">
        <span class="flex items-center gap-1.5 text-[var(--muted)]">
          <span class="w-2 h-2 rounded-full bg-[#FBBF24]" />
          {{ $t('SINAL_REPORTS.MONTHLY.HUMAN') }}
        </span>
        <span class="font-mono text-[var(--text)]">{{
          formatNumber(months[hovered].human)
        }}</span>
      </div>
      <div class="flex items-center justify-between gap-3 mt-1">
        <span class="flex items-center gap-1.5 text-[var(--muted)]">
          <span class="w-2 h-2 rounded-full bg-[var(--muted)]" />
          {{ $t('SINAL_REPORTS.MONTHLY.RECEIVED') }}
        </span>
        <span class="font-mono text-[var(--text)]">{{
          formatNumber(months[hovered].received)
        }}</span>
      </div>
    </div>
  </div>
</template>
