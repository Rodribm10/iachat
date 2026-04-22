<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  summary: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});

const { t } = useI18n();

const cards = computed(() => {
  if (!props.summary) return [];
  const s = props.summary.status || {};
  const r = props.summary.retention || {};
  const p = props.summary.pix || {};
  const K = 'CAPTAIN_REPORTS.RETENTION.KPI';
  return [
    {
      label: t(`${K}.ACTIVE`),
      value: s.active ?? 0,
      hint: t(`${K}.ACTIVE_HINT`),
      tone: 'green',
    },
    {
      label: t(`${K}.RECURRING`),
      value: s.recurring ?? 0,
      hint: t(`${K}.RECURRING_HINT`),
      tone: 'blue',
    },
    {
      label: t(`${K}.RETURN_30D`),
      value: `${Math.round((r.last_30d ?? 0) * 100)}%`,
      hint: t(`${K}.RETURN_30D_HINT`),
      tone: 'indigo',
    },
    {
      label: t(`${K}.PIX_CONVERSION`),
      value: `${Math.round((p.conversion_rate ?? 0) * 100)}%`,
      hint: t(`${K}.PIX_CONVERSION_HINT`, {
        paid: p.paid ?? 0,
        generated: p.generated ?? 0,
      }),
      tone: 'amber',
    },
  ];
});

const toneClass = {
  green:
    'bg-emerald-50 text-emerald-700 dark:bg-emerald-900/20 dark:text-emerald-300',
  blue: 'bg-sky-50 text-sky-700 dark:bg-sky-900/20 dark:text-sky-300',
  indigo:
    'bg-indigo-50 text-indigo-700 dark:bg-indigo-900/20 dark:text-indigo-300',
  amber: 'bg-amber-50 text-amber-700 dark:bg-amber-900/20 dark:text-amber-300',
};
</script>

<template>
  <div
    v-if="loading"
    class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4"
  >
    <div
      v-for="i in 4"
      :key="i"
      class="h-28 animate-pulse rounded-lg bg-slate-100 dark:bg-slate-800"
    />
  </div>

  <div
    v-else-if="summary"
    class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4"
  >
    <div
      v-for="card in cards"
      :key="card.label"
      class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-700 dark:bg-slate-800"
    >
      <div class="flex items-center justify-between">
        <span
          class="text-xs font-medium uppercase tracking-wide text-slate-500 dark:text-slate-400"
        >
          {{ card.label }}
        </span>
        <span
          :class="toneClass[card.tone]"
          class="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase"
        >
          {{ card.tone }}
        </span>
      </div>
      <div class="mt-3 text-3xl font-bold text-slate-900 dark:text-slate-50">
        {{ card.value }}
      </div>
      <div class="mt-1 text-xs text-slate-500 dark:text-slate-400">
        {{ card.hint }}
      </div>
    </div>
  </div>

  <div v-else class="text-sm text-slate-500">
    {{ $t('CAPTAIN_REPORTS.RETENTION.NO_DATA') }}
  </div>
</template>
