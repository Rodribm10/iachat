<script setup>
// Seletor de período compartilhado das páginas Sinal: presets relativos
// (hoje / 7 / 14 / 30 dias) + intervalo personalizado, com botão de
// atualizar. O componente não guarda o range calculado — só emite
// `refresh` para o pai recalcular na hora do fetch via
// helpers.computePeriodRange, garantindo que presets relativos sempre usem
// o instante atual (em vez de congelar no momento em que a página abriu).
defineProps({
  preset: { type: String, default: '7' },
  customStart: { type: String, default: '' },
  customEnd: { type: String, default: '' },
  isLoading: { type: Boolean, default: false },
});

defineEmits([
  'update:preset',
  'update:customStart',
  'update:customEnd',
  'refresh',
]);
</script>

<template>
  <div class="flex flex-wrap items-center gap-1.5">
    <select
      :value="preset"
      class="h-8 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2.5 text-xs font-semibold text-[var(--text)] outline-none focus:border-[var(--accent)]"
      @change="$emit('update:preset', $event.target.value)"
    >
      <option value="today">
        {{ $t('SINAL_REPORTS.OVERVIEW.PERIOD_TODAY') }}
      </option>
      <option value="7">
        {{ $t('SINAL_REPORTS.PRIVADO.PERIOD_SHORT', { days: 7 }) }}
      </option>
      <option value="14">
        {{ $t('SINAL_REPORTS.PRIVADO.PERIOD_SHORT', { days: 14 }) }}
      </option>
      <option value="30">
        {{ $t('SINAL_REPORTS.PRIVADO.PERIOD_SHORT', { days: 30 }) }}
      </option>
      <option value="custom">
        {{ $t('SINAL_REPORTS.OVERVIEW.PERIOD_CUSTOM') }}
      </option>
    </select>
    <template v-if="preset === 'custom'">
      <input
        :value="customStart"
        type="date"
        class="h-8 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2 text-xs text-[var(--text)]"
        @change="$emit('update:customStart', $event.target.value)"
      />
      <input
        :value="customEnd"
        type="date"
        class="h-8 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2 text-xs text-[var(--text)]"
        @change="$emit('update:customEnd', $event.target.value)"
      />
    </template>
    <button
      type="button"
      :disabled="isLoading"
      :title="$t('SINAL_REPORTS.PERIOD_PICKER.REFRESH')"
      class="flex h-8 w-8 items-center justify-center rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] text-[var(--text)] transition-colors hover:border-[var(--accent)] disabled:opacity-60"
      @click="$emit('refresh')"
    >
      <span
        class="i-lucide-refresh-cw size-3.5"
        :class="{ 'animate-spin': isLoading }"
      />
    </button>
  </div>
</template>
