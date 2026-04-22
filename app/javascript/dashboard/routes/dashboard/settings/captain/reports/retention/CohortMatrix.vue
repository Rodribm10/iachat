<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  data: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});

const { t } = useI18n();

const cohorts = computed(() => props.data?.cohorts ?? []);
const maxOffset = computed(() => props.data?.max_offset_months ?? 12);

const offsetHeaders = computed(() =>
  Array.from({ length: maxOffset.value + 1 }, (_, i) => `M+${i}`)
);

const MONTH_KEYS = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

function formatMonth(iso) {
  if (!iso) return '';
  const date = new Date(iso);
  return `${MONTH_KEYS[date.getMonth()]}/${String(date.getFullYear()).slice(2)}`;
}

function cellStyle(rate) {
  if (rate === null || rate === undefined) return {};
  if (rate === 0) {
    return {
      background: 'rgba(148, 163, 184, 0.12)',
      color: 'var(--text-muted, #94a3b8)',
    };
  }
  const pct = Math.min(rate, 1);
  const intensity = 0.2 + pct * 0.8;
  return {
    background: `rgba(16, 185, 129, ${intensity})`,
    color: pct > 0.5 ? '#fff' : '#065f46',
  };
}

function cellTitle(cell) {
  return t('CAPTAIN_REPORTS.RETENTION.COHORT.CELL_TITLE', {
    count: cell.count,
    rate: (cell.rate * 100).toFixed(1),
  });
}

function exportCsv() {
  if (!cohorts.value.length) return;
  const header = ['cohort,size,' + offsetHeaders.value.join(',')];
  const rows = cohorts.value.map(c => {
    const cells = c.retention
      .map(r => `${(r.rate * 100).toFixed(1)}%`)
      .join(',');
    return `${formatMonth(c.cohort)},${c.size},${cells}`;
  });
  const csv = header.concat(rows).join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'retention-cohort.csv';
  a.click();
  URL.revokeObjectURL(url);
}
</script>

<template>
  <div
    class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-700 dark:bg-slate-800"
  >
    <div class="mb-3 flex items-center justify-between">
      <div>
        <h3 class="text-base font-semibold text-slate-800 dark:text-slate-100">
          {{ $t('CAPTAIN_REPORTS.RETENTION.COHORT.TITLE') }}
        </h3>
        <p class="text-xs text-slate-500">
          {{ $t('CAPTAIN_REPORTS.RETENTION.COHORT.SUBTITLE') }}
        </p>
      </div>
      <button
        v-if="cohorts.length"
        class="rounded-md border border-slate-200 bg-white px-3 py-1.5 text-xs font-medium hover:bg-slate-50 dark:border-slate-700 dark:bg-slate-800 dark:hover:bg-slate-700"
        @click="exportCsv"
      >
        {{ $t('CAPTAIN_REPORTS.RETENTION.COHORT.EXPORT_CSV') }}
      </button>
    </div>

    <div
      v-if="loading"
      class="h-48 animate-pulse rounded bg-slate-100 dark:bg-slate-900"
    />

    <div
      v-else-if="!cohorts.length"
      class="py-8 text-center text-sm text-slate-500"
    >
      {{ $t('CAPTAIN_REPORTS.RETENTION.COHORT.EMPTY') }}
    </div>

    <div v-else class="overflow-x-auto">
      <table class="cohort-table min-w-full border-separate">
        <thead>
          <tr>
            <th
              class="px-3 py-2 text-left text-xs font-semibold text-slate-500"
            >
              {{ $t('CAPTAIN_REPORTS.RETENTION.COHORT.COL_COHORT') }}
            </th>
            <th
              class="px-3 py-2 text-right text-xs font-semibold text-slate-500"
            >
              {{ $t('CAPTAIN_REPORTS.RETENTION.COHORT.COL_SIZE') }}
            </th>
            <th
              v-for="h in offsetHeaders"
              :key="h"
              class="px-2 py-2 text-center text-xs font-semibold text-slate-500"
            >
              {{ h }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in cohorts" :key="row.cohort">
            <td
              class="whitespace-nowrap px-3 py-1 text-sm font-medium text-slate-700 dark:text-slate-200"
            >
              {{ formatMonth(row.cohort) }}
            </td>
            <td
              class="px-3 py-1 text-right text-sm tabular-nums text-slate-600 dark:text-slate-300"
            >
              {{ row.size }}
            </td>
            <td
              v-for="cell in row.retention"
              :key="cell.month_offset"
              class="rounded px-2 py-1 text-center text-xs font-semibold tabular-nums"
              :style="cellStyle(cell.rate)"
              :title="cellTitle(cell)"
            >
              {{ (cell.rate * 100).toFixed(0) }}%
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.cohort-table {
  border-spacing: 2px;
}
</style>
