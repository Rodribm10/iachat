<script setup>
import { computed } from 'vue';

const props = defineProps({
  summary: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});

const data = computed(() => {
  if (!props.summary) return null;
  const flow = props.summary.flow || {};
  const status = props.summary.status || {};
  return {
    newCount: flow.new ?? 0,
    returnedCount: flow.returned ?? 0,
    totalTouches: flow.total_touches ?? 0,
    sleeping: status.sleeping ?? 0,
    atRisk: status.at_risk ?? 0,
    churned: status.churned ?? 0,
  };
});

const newPct = computed(() => {
  if (!data.value || data.value.totalTouches === 0) return 0;
  return Math.round((data.value.newCount / data.value.totalTouches) * 100);
});

const newBarStyle = computed(() => ({ width: `${newPct.value}%` }));
const returnedBarStyle = computed(() => ({ width: `${100 - newPct.value}%` }));
</script>

<template>
  <div
    class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-700 dark:bg-slate-800"
  >
    <h3 class="mb-3 text-base font-semibold text-slate-800 dark:text-slate-100">
      {{ $t('CAPTAIN_REPORTS.RETENTION.FLOW.TITLE') }}
    </h3>

    <div
      v-if="loading"
      class="h-24 animate-pulse rounded bg-slate-100 dark:bg-slate-900"
    />

    <template v-else-if="data">
      <div class="mb-4 grid grid-cols-3 gap-4">
        <div>
          <div
            class="text-2xl font-bold text-emerald-600 dark:text-emerald-400"
          >
            {{ data.newCount }}
          </div>
          <div class="text-xs text-slate-500">
            {{ $t('CAPTAIN_REPORTS.RETENTION.FLOW.NEW_IN_PERIOD') }}
          </div>
        </div>
        <div>
          <div class="text-2xl font-bold text-sky-600 dark:text-sky-400">
            {{ data.returnedCount }}
          </div>
          <div class="text-xs text-slate-500">
            {{ $t('CAPTAIN_REPORTS.RETENTION.FLOW.RETURNED_IN_PERIOD') }}
          </div>
        </div>
        <div>
          <div class="text-2xl font-bold text-slate-900 dark:text-slate-100">
            {{ data.totalTouches }}
          </div>
          <div class="text-xs text-slate-500">
            {{ $t('CAPTAIN_REPORTS.RETENTION.FLOW.TOTAL_TOUCHES') }}
          </div>
        </div>
      </div>

      <!-- Barra de proporção novos vs recorrentes -->
      <div
        class="mb-4 h-2 w-full overflow-hidden rounded-full bg-slate-100 dark:bg-slate-900"
      >
        <div class="flex h-full">
          <div class="bg-emerald-500" :style="newBarStyle" />
          <div class="bg-sky-500" :style="returnedBarStyle" />
        </div>
      </div>

      <!-- Status absoluto -->
      <div class="mt-5 border-t border-slate-100 pt-4 dark:border-slate-700">
        <div
          class="mb-2 text-xs font-medium uppercase tracking-wide text-slate-500"
        >
          {{ $t('CAPTAIN_REPORTS.RETENTION.FLOW.BASE_STATUS') }}
        </div>
        <div class="grid grid-cols-3 gap-3 text-sm">
          <div class="rounded bg-amber-50 px-3 py-2 dark:bg-amber-900/10">
            <div class="font-semibold text-amber-700 dark:text-amber-300">
              {{
                $t('CAPTAIN_REPORTS.RETENTION.FLOW.SLEEPING', {
                  count: data.sleeping,
                })
              }}
            </div>
            <div class="text-xs text-slate-500">
              {{ $t('CAPTAIN_REPORTS.RETENTION.FLOW.SLEEPING_HINT') }}
            </div>
          </div>
          <div class="rounded bg-orange-50 px-3 py-2 dark:bg-orange-900/10">
            <div class="font-semibold text-orange-700 dark:text-orange-300">
              {{
                $t('CAPTAIN_REPORTS.RETENTION.FLOW.AT_RISK', {
                  count: data.atRisk,
                })
              }}
            </div>
            <div class="text-xs text-slate-500">
              {{ $t('CAPTAIN_REPORTS.RETENTION.FLOW.AT_RISK_HINT') }}
            </div>
          </div>
          <div class="rounded bg-rose-50 px-3 py-2 dark:bg-rose-900/10">
            <div class="font-semibold text-rose-700 dark:text-rose-300">
              {{
                $t('CAPTAIN_REPORTS.RETENTION.FLOW.CHURNED', {
                  count: data.churned,
                })
              }}
            </div>
            <div class="text-xs text-slate-500">
              {{ $t('CAPTAIN_REPORTS.RETENTION.FLOW.CHURNED_HINT') }}
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
