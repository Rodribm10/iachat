<script setup>
import { formatNumber } from './helpers';

defineProps({
  icon: { type: String, required: true },
  iconClass: { type: String, default: 'text-[var(--accent)]' },
  label: { type: String, required: true },
  value: { type: Number, default: 0 },
  hint: { type: String, default: '' },
  badge: { type: String, default: '' },
  badgeNegative: { type: Boolean, default: false },
});
</script>

<template>
  <div
    class="group relative overflow-hidden rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-4 sm:p-5 transition-all duration-200 hover:border-[var(--accent-border)]"
  >
    <div class="flex items-center justify-between mb-2 sm:mb-3">
      <div class="flex items-center gap-2">
        <div
          class="flex h-7 w-7 items-center justify-center rounded-lg bg-[var(--surface-2)]"
        >
          <span class="size-4" :class="[icon, iconClass]" />
        </div>
        <span class="text-xs font-semibold text-[var(--muted)]">{{
          label
        }}</span>
      </div>
      <span
        v-if="badge"
        class="inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold"
        :class="
          badgeNegative
            ? 'bg-red-500/10 text-red-600 dark:text-red-400'
            : 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
        "
      >
        {{ badge }}
      </span>
    </div>
    <div
      class="font-display text-2xl sm:text-3xl font-bold tracking-tight text-[var(--text)]"
    >
      {{ formatNumber(value) }}
    </div>
    <div class="mt-1 text-[11.5px] text-[var(--muted-2)] font-normal truncate">
      {{ hint }}
    </div>
  </div>
</template>
