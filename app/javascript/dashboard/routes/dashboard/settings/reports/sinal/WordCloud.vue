<script setup>
import { computed } from 'vue';
import { SINAL_PALETTE } from './helpers';

const props = defineProps({
  items: {
    // [{ topic, count, color? }]
    type: Array,
    default: () => [],
  },
  clickable: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['pick']);

const max = computed(() => Math.max(1, ...props.items.map(item => item.count)));
const min = computed(() =>
  props.items.length ? Math.min(...props.items.map(item => item.count)) : 0
);
const span = computed(() => Math.max(1, max.value - min.value));

const styleFor = (item, index) => {
  const t = (item.count - min.value) / span.value;
  const size = 13 + Math.round(t * 15);
  const opacity = 0.6 + t * 0.4;
  const color = item.color || SINAL_PALETTE[index % SINAL_PALETTE.length];
  return { fontSize: `${size}px`, color, opacity };
};
</script>

<template>
  <div
    v-if="!items.length"
    class="py-8 text-center text-[var(--muted-2)] text-xs"
  >
    {{ $t('SINAL_REPORTS.CLOUD_EMPTY') }}
  </div>
  <div v-else class="flex flex-wrap items-center gap-x-3.5 gap-y-2">
    <component
      :is="clickable ? 'button' : 'span'"
      v-for="(item, index) in items"
      :key="item.topic"
      :title="`${item.count}`"
      class="font-semibold leading-none tracking-tight transition-all"
      :class="
        clickable ? 'cursor-pointer hover:opacity-100 hover:scale-105' : ''
      "
      :style="styleFor(item, index)"
      @click="clickable ? emit('pick', item.topic) : undefined"
    >
      {{ item.topic }}
    </component>
  </div>
</template>
