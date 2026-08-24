<script setup>
// Sparkline em área com gradiente, como no card "Volume recebido" do privado.
import { computed } from 'vue';

const props = defineProps({
  points: {
    // [Number]
    type: Array,
    default: () => [],
  },
});

const WIDTH = 120;
const HEIGHT = 34;

const path = computed(() => {
  if (props.points.length < 2) return '';
  const max = Math.max(1, ...props.points);
  const step = WIDTH / (props.points.length - 1);
  return props.points
    .map(
      (v, i) =>
        `${i === 0 ? 'M' : 'L'}${(i * step).toFixed(1)},${(
          HEIGHT -
          2 -
          (v / max) * (HEIGHT - 6)
        ).toFixed(1)}`
    )
    .join(' ');
});

const areaPath = computed(() =>
  path.value ? `${path.value} L${WIDTH},${HEIGHT} L0,${HEIGHT} Z` : ''
);
</script>

<template>
  <svg
    :viewBox="`0 0 ${WIDTH} ${HEIGHT}`"
    class="w-full h-[34px]"
    preserveAspectRatio="none"
  >
    <defs>
      <linearGradient id="sinal-spark-grad" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="var(--accent)" stop-opacity="0.3" />
        <stop offset="100%" stop-color="var(--accent)" stop-opacity="0" />
      </linearGradient>
    </defs>
    <path v-if="areaPath" :d="areaPath" fill="url(#sinal-spark-grad)" />
    <path
      v-if="path"
      :d="path"
      fill="none"
      stroke="var(--accent)"
      stroke-width="1.8"
      vector-effect="non-scaling-stroke"
    />
  </svg>
</template>
