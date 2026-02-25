<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  marker: {
    type: Object,
    default: () => ({}),
  },
  compact: {
    type: Boolean,
    default: false,
  },
  clickable: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['click']);
const { t } = useI18n();

const markerStatus = computed(() => props.marker?.status || 'draft');

const statusLabel = computed(() => {
  const key = `CAPTAIN_RESERVATIONS.STATUS.${markerStatus.value.toUpperCase()}`;
  const translated = t(key);
  return translated === key
    ? props.marker?.status_label || markerStatus.value
    : translated;
});

const amountLabel = computed(() =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    Number(props.marker?.amount || 0)
  )
);

const checkInLabel = computed(() => {
  if (!props.marker?.check_in_at) return null;
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  }).format(new Date(props.marker.check_in_at));
});

const stateClass = computed(() => {
  const map = {
    draft: 'bg-n-slate-3 text-n-slate-12',
    pending_payment: 'bg-n-amber-3 text-n-amber-11',
    confirmed: 'bg-n-teal-3 text-n-teal-11',
    cancelled: 'bg-n-ruby-3 text-n-ruby-11',
  };

  return map[markerStatus.value] || map.draft;
});
</script>

<template>
  <button
    type="button"
    class="inline-flex items-center max-w-full gap-1 px-2 py-1 text-xs font-medium rounded-full"
    :class="[
      stateClass,
      { 'cursor-pointer': clickable, 'cursor-default': !clickable },
    ]"
    @click.stop="emit('click')"
  >
    <span class="truncate">{{ statusLabel }}</span>
    <span v-if="!compact" class="opacity-80">•</span>
    <span v-if="!compact" class="opacity-80">{{ amountLabel }}</span>
    <span v-if="!compact && checkInLabel" class="opacity-80">
      • {{ checkInLabel }}
    </span>
  </button>
</template>
