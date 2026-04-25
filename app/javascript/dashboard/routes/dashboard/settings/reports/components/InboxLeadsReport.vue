<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';
import ReportFilters from './ReportFilters.vue';
import ReportMetricCard from './ReportMetricCard.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  inboxId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const filters = ref({
  from: null,
  to: null,
  groupBy: { id: 1, period: 'day' },
});

const isFetching = computed(() => store.getters.getInboxLeadsSummaryFetching);
const rows = computed(() => store.getters.getInboxLeadsSummary || []);

const totals = computed(() => {
  return rows.value.reduce(
    (acc, row) => {
      acc.new_leads += row.new_leads || 0;
      acc.returning += row.returning || 0;
      acc.others += row.others || 0;
      return acc;
    },
    { new_leads: 0, returning: 0, others: 0 }
  );
});

const totalConversations = computed(
  () => totals.value.new_leads + totals.value.returning + totals.value.others
);

const formatPeriodLabel = (iso, period) => {
  const date = new Date(iso);
  if (period === 'month') return format(date, 'MMM/yy');
  if (period === 'week') return format(date, "'S'II/yy");
  return format(date, 'dd/MM');
};

const chartCollection = computed(() => {
  const period = filters.value.groupBy?.period || 'day';
  return {
    labels: rows.value.map(r => formatPeriodLabel(r.period, period)),
    datasets: [
      {
        label: t('INBOX_REPORTS.LEADS.CHART.NEW_LEADS'),
        backgroundColor: '#10B981',
        data: rows.value.map(r => r.new_leads),
      },
      {
        label: t('INBOX_REPORTS.LEADS.CHART.RETURNING'),
        backgroundColor: '#3B82F6',
        data: rows.value.map(r => r.returning),
      },
      {
        label: t('INBOX_REPORTS.LEADS.CHART.OTHERS'),
        backgroundColor: '#9CA3AF',
        data: rows.value.map(r => r.others),
      },
    ],
  };
});

const chartOptions = {
  plugins: {
    legend: { display: true, position: 'bottom' },
  },
  scales: {
    x: { stacked: true, grid: { drawOnChartArea: false } },
    y: { stacked: true, beginAtZero: true, ticks: { stepSize: 1 } },
  },
};

const fetchData = () => {
  if (!filters.value.from || !filters.value.to) return;
  store.dispatch('fetchInboxLeadsSummary', {
    inboxId: props.inboxId,
    from: filters.value.from,
    to: filters.value.to,
    groupBy: filters.value.groupBy?.period || 'day',
  });
};

const onFilterChange = payload => {
  filters.value = {
    from: payload.from,
    to: payload.to,
    groupBy: payload.groupBy || filters.value.groupBy,
  };
  fetchData();
};

watch(
  () => props.inboxId,
  () => fetchData()
);
</script>

<template>
  <div class="flex flex-col gap-6">
    <ReportFilters
      filter-type="inboxes"
      :selected-item="{ id: Number(inboxId) }"
      :show-business-hours="false"
      :show-entity-filter="false"
      @filter-change="onFilterChange"
    />

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <ReportMetricCard
        :label="$t('INBOX_REPORTS.LEADS.METRICS.NEW_LEADS.LABEL')"
        :value="String(totals.new_leads)"
        :info-text="$t('INBOX_REPORTS.LEADS.METRICS.NEW_LEADS.INFO')"
      />
      <ReportMetricCard
        :label="$t('INBOX_REPORTS.LEADS.METRICS.RETURNING.LABEL')"
        :value="String(totals.returning)"
        :info-text="$t('INBOX_REPORTS.LEADS.METRICS.RETURNING.INFO')"
      />
      <ReportMetricCard
        :label="$t('INBOX_REPORTS.LEADS.METRICS.OTHERS.LABEL')"
        :value="String(totals.others)"
        :info-text="$t('INBOX_REPORTS.LEADS.METRICS.OTHERS.INFO')"
      />
    </div>

    <div
      class="bg-n-solid-1 border border-n-weak rounded-lg p-4 min-h-[320px] flex items-center justify-center"
    >
      <Spinner v-if="isFetching" />
      <div v-else-if="rows.length === 0" class="text-sm text-n-slate-11">
        {{ $t('INBOX_REPORTS.LEADS.EMPTY') }}
      </div>
      <div v-else class="w-full h-[320px]">
        <BarChart :collection="chartCollection" :chart-options="chartOptions" />
      </div>
    </div>

    <div class="text-xs text-n-slate-11">
      {{ $t('INBOX_REPORTS.LEADS.TOTAL', { count: totalConversations }) }}
    </div>
  </div>
</template>
