<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CaptainReportsAPI from 'dashboard/api/captain/reports';
import KpiCards from './KpiCards.vue';
import FlowCard from './FlowCard.vue';
import CohortMatrix from './CohortMatrix.vue';

const { t } = useI18n();

const summary = ref(null);
const cohort = ref(null);
const loadingSummary = ref(false);
const loadingCohort = ref(false);

const periodPreset = ref('this_month');
const customStart = ref('');
const customEnd = ref('');

function formatLocalDate(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function getPeriodDates() {
  const end = new Date();
  const start = new Date();
  switch (periodPreset.value) {
    case 'this_month':
      start.setDate(1);
      break;
    case 'last_30_days':
      start.setDate(end.getDate() - 29);
      break;
    case 'last_90_days':
      start.setDate(end.getDate() - 89);
      break;
    case 'custom':
      return { start: customStart.value, end: customEnd.value };
    default:
      start.setDate(1);
  }
  return { start: formatLocalDate(start), end: formatLocalDate(end) };
}

async function fetchSummary() {
  loadingSummary.value = true;
  try {
    const dates = getPeriodDates();
    const { data } = await CaptainReportsAPI.getRetention({
      start_date: dates.start,
      end_date: dates.end,
    });
    summary.value = data;
  } catch (err) {
    useAlert(t('CAPTAIN_REPORTS.RETENTION.ERRORS.SUMMARY'));
  } finally {
    loadingSummary.value = false;
  }
}

async function fetchCohort() {
  loadingCohort.value = true;
  try {
    const { data } = await CaptainReportsAPI.getRetentionCohort({
      history_months: 12,
    });
    cohort.value = data;
  } catch (err) {
    useAlert(t('CAPTAIN_REPORTS.RETENTION.ERRORS.COHORT'));
  } finally {
    loadingCohort.value = false;
  }
}

function refresh() {
  fetchSummary();
  fetchCohort();
}

onMounted(refresh);
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-wrap items-center gap-3">
      <label class="text-sm font-medium text-slate-600 dark:text-slate-300">
        {{ $t('CAPTAIN_REPORTS.RETENTION.PERIOD_LABEL') }}:
      </label>
      <select
        v-model="periodPreset"
        class="rounded-md border border-slate-200 bg-white px-3 py-1.5 text-sm dark:border-slate-700 dark:bg-slate-800"
        @change="fetchSummary"
      >
        <option value="this_month">
          {{ $t('CAPTAIN_REPORTS.RETENTION.PERIOD_THIS_MONTH') }}
        </option>
        <option value="last_30_days">
          {{ $t('CAPTAIN_REPORTS.RETENTION.PERIOD_LAST_30') }}
        </option>
        <option value="last_90_days">
          {{ $t('CAPTAIN_REPORTS.RETENTION.PERIOD_LAST_90') }}
        </option>
        <option value="custom">
          {{ $t('CAPTAIN_REPORTS.RETENTION.PERIOD_CUSTOM') }}
        </option>
      </select>
      <template v-if="periodPreset === 'custom'">
        <input
          v-model="customStart"
          type="date"
          class="rounded-md border border-slate-200 bg-white px-2 py-1.5 text-sm dark:border-slate-700 dark:bg-slate-800"
        />
        <input
          v-model="customEnd"
          type="date"
          class="rounded-md border border-slate-200 bg-white px-2 py-1.5 text-sm dark:border-slate-700 dark:bg-slate-800"
        />
        <button
          class="rounded-md bg-woot-500 px-3 py-1.5 text-sm text-white hover:bg-woot-600"
          @click="fetchSummary"
        >
          {{ $t('CAPTAIN_REPORTS.RETENTION.APPLY') }}
        </button>
      </template>
    </div>

    <KpiCards :summary="summary" :loading="loadingSummary" />
    <FlowCard :summary="summary" :loading="loadingSummary" />
    <CohortMatrix :data="cohort" :loading="loadingCohort" />
  </div>
</template>
