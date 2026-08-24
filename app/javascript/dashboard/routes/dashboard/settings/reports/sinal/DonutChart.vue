<script setup>
// Donut em SVG puro (réplica do PieChart/recharts do Panorama visual do Sinal).
import { computed, ref } from 'vue';
import { formatNumber } from './helpers';

const props = defineProps({
  items: {
    // [{ name, value, color }]
    type: Array,
    default: () => [],
  },
  unit: { type: String, default: '' },
  size: { type: Number, default: 196 },
});

const OUTER = 78;
const INNER = 54;
const CENTER = 100;
const PAD_ANGLE = 2;

const hovered = ref(null);

const total = computed(() =>
  props.items.reduce((sum, item) => sum + item.value, 0)
);

const visible = computed(() => props.items.filter(item => item.value > 0));

const polar = (radius, angleDeg) => {
  const rad = ((angleDeg - 90) * Math.PI) / 180;
  return [CENTER + radius * Math.cos(rad), CENTER + radius * Math.sin(rad)];
};

const arcs = computed(() => {
  if (!total.value) return [];
  const count = visible.value.length;
  const pad = count > 1 ? PAD_ANGLE : 0;
  const usable = 360 - pad * count;
  let cursor = 0;
  return visible.value.map(item => {
    const sweep = (item.value / total.value) * usable;
    const start = cursor + pad / 2;
    const end = start + sweep;
    cursor = end + pad / 2;
    const large = sweep > 180 ? 1 : 0;
    const [x1, y1] = polar(OUTER, start);
    const [x2, y2] = polar(OUTER, end);
    const [x3, y3] = polar(INNER, end);
    const [x4, y4] = polar(INNER, start);
    return {
      ...item,
      d: `M${x1.toFixed(2)},${y1.toFixed(2)} A${OUTER},${OUTER} 0 ${large} 1 ${x2.toFixed(2)},${y2.toFixed(2)} L${x3.toFixed(2)},${y3.toFixed(2)} A${INNER},${INNER} 0 ${large} 0 ${x4.toFixed(2)},${y4.toFixed(2)} Z`,
    };
  });
});
</script>

<template>
  <div
    class="relative flex items-center justify-center"
    :style="{ height: `${size}px` }"
  >
    <div v-if="!total" class="text-[12px] text-[var(--muted-2)]">
      {{ $t('SINAL_REPORTS.CLOUD_EMPTY') }}
    </div>
    <svg
      v-else
      viewBox="0 0 200 200"
      class="h-full"
      @mouseleave="hovered = null"
    >
      <path
        v-for="(arc, index) in arcs"
        :key="arc.name"
        :d="arc.d"
        :fill="arc.color"
        :opacity="hovered === null || hovered === index ? 1 : 0.4"
        stroke="var(--surface)"
        stroke-width="2"
        @mouseenter="hovered = index"
      />
      <text
        x="100"
        y="96"
        text-anchor="middle"
        class="fill-[var(--text)] text-[18px] font-semibold"
      >
        {{ formatNumber(total) }}
      </text>
      <text
        x="100"
        y="118"
        text-anchor="middle"
        class="fill-[var(--muted-2)] text-[10px]"
      >
        {{ unit }}
      </text>
    </svg>
    <div
      v-if="hovered !== null && arcs[hovered]"
      class="absolute top-1 right-1 bg-[var(--surface-2)] border border-[var(--border)] rounded-lg px-2.5 py-1.5 text-[11.5px] shadow-lg pointer-events-none"
    >
      <div class="font-semibold text-[var(--text)]">
        {{ arcs[hovered].name }}
      </div>
      <div class="text-[var(--muted)] mt-0.5">
        {{ `${formatNumber(arcs[hovered].value)} ${unit}` }}
      </div>
    </div>
  </div>
</template>
