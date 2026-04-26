<script setup>
import { ref, computed, onMounted } from 'vue';
import ReportsAPI from 'dashboard/api/reports';
import ReportFilters from './components/ReportFilters.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import ReportHeader from './components/ReportHeader.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const filters = ref({ from: 0, to: 0, inboxId: null });
const isLoadingFunnel = ref(false);
const isLoadingBenchmark = ref(false);

const funnel = ref({
  leads: { total: 0, new: 0, returning: 0 },
  reservations: { created: 0, paid: 0 },
  conversion_rates: {
    lead_to_paid_reservation: 0,
    lead_to_any_reservation: 0,
    created_to_paid: 0,
  },
});

const benchmark = ref([]);

const fetchFunnel = () => {
  if (!filters.value.from || !filters.value.to) return;
  isLoadingFunnel.value = true;
  ReportsAPI.getConversionFunnel(filters.value)
    .then(({ data }) => {
      funnel.value = data;
    })
    .finally(() => {
      isLoadingFunnel.value = false;
    });
};

const fetchBenchmark = () => {
  if (!filters.value.from || !filters.value.to) return;
  isLoadingBenchmark.value = true;
  ReportsAPI.getInboxBenchmarking({
    from: filters.value.from,
    to: filters.value.to,
  })
    .then(({ data }) => {
      benchmark.value = data;
    })
    .finally(() => {
      isLoadingBenchmark.value = false;
    });
};

const onFilterChange = ({ from, to, inboxes }) => {
  filters.value = {
    from,
    to,
    inboxId: inboxes?.id || null,
  };
  fetchFunnel();
  fetchBenchmark();
};

const benchmarkGrouped = computed(() => {
  const groups = new Map();
  benchmark.value.forEach(row => {
    const brand = row.brand_name || '— Sem marca —';
    if (!groups.has(brand)) groups.set(brand, []);
    groups.get(brand).push(row);
  });
  return [...groups.entries()].map(([brand, rows]) => {
    const totalLeads = rows.reduce((s, r) => s + r.leads_total, 0);
    const totalPaid = rows.reduce((s, r) => s + r.reservations_paid, 0);
    const brandRate = totalLeads === 0 ? 0 : (totalPaid / totalLeads) * 100;
    return { brand, rows, brandRate: Math.round(brandRate * 10) / 10 };
  });
});

const formatNumber = n => Number(n || 0).toLocaleString();
const formatPct = n => `${Number(n || 0).toFixed(1)}%`;

const variationFromBrand = (rowRate, brandRate) => {
  if (brandRate === 0) return null;
  return Math.round((rowRate - brandRate) * 10) / 10;
};

onMounted(() => {});
</script>

<template>
  <ReportHeader :header-title="$t('DIRECTORY_DASHBOARD.HEADER')" />

  <div
    class="bg-n-amber-3 border border-n-amber-7 rounded-lg p-3 mb-4 text-sm text-n-slate-12"
  >
    <strong>{{ $t('DIRECTORY_DASHBOARD.BANNER.TITLE') }}</strong>
    {{ $t('DIRECTORY_DASHBOARD.BANNER.BODY') }}
  </div>

  <div class="flex flex-col gap-4">
    <ReportFilters
      filter-type="inboxes"
      :show-group-by="false"
      :show-business-hours="false"
      :navigate-on-entity-filter="false"
      @filter-change="onFilterChange"
    />

    <div
      class="bg-n-solid-2 shadow outline-1 outline outline-n-container rounded-xl px-6 py-5"
    >
      <h3 class="text-base font-semibold m-0 mb-4">
        {{ $t('DIRECTORY_DASHBOARD.HEADLINE_NUMBERS') }}
      </h3>
      <Spinner v-if="isLoadingFunnel" />
      <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <ReportMetricCard
          :label="$t('DIRECTORY_DASHBOARD.METRICS.LEADS_TOTAL.LABEL')"
          :value="formatNumber(funnel.leads.total)"
          :info-text="$t('DIRECTORY_DASHBOARD.METRICS.LEADS_TOTAL.TOOLTIP')"
        />
        <ReportMetricCard
          :label="$t('DIRECTORY_DASHBOARD.METRICS.LEADS_NEW.LABEL')"
          :value="formatNumber(funnel.leads.new)"
          :info-text="$t('DIRECTORY_DASHBOARD.METRICS.LEADS_NEW.TOOLTIP')"
        />
        <ReportMetricCard
          :label="$t('DIRECTORY_DASHBOARD.METRICS.LEADS_RETURNING.LABEL')"
          :value="formatNumber(funnel.leads.returning)"
          :info-text="$t('DIRECTORY_DASHBOARD.METRICS.LEADS_RETURNING.TOOLTIP')"
        />
        <ReportMetricCard
          :label="$t('DIRECTORY_DASHBOARD.METRICS.CONVERSION_RATE.LABEL')"
          :value="formatPct(funnel.conversion_rates.lead_to_paid_reservation)"
          :info-text="$t('DIRECTORY_DASHBOARD.METRICS.CONVERSION_RATE.TOOLTIP')"
        />
      </div>
    </div>

    <div
      class="bg-n-solid-2 shadow outline-1 outline outline-n-container rounded-xl px-6 py-5"
    >
      <h3 class="text-base font-semibold m-0 mb-4">
        {{ $t('DIRECTORY_DASHBOARD.FUNNEL.TITLE') }}
      </h3>
      <Spinner v-if="isLoadingFunnel" />
      <div v-else class="space-y-3">
        <div class="flex items-center gap-4">
          <div class="w-32 text-sm text-n-slate-11">
            {{ $t('DIRECTORY_DASHBOARD.FUNNEL.STAGE_LEADS') }}
          </div>
          <div class="flex-1 bg-n-blue-9 text-white px-4 py-3 rounded-lg">
            <span class="text-lg font-semibold">{{
              formatNumber(funnel.leads.total)
            }}</span>
          </div>
          <div class="w-24 text-sm text-n-slate-11 text-right">
            {{ formatPct(100) }}
          </div>
        </div>
        <div class="flex items-center gap-4">
          <div class="w-32 text-sm text-n-slate-11">
            {{ $t('DIRECTORY_DASHBOARD.FUNNEL.STAGE_RESERVATIONS') }}
          </div>
          <div
            class="flex-1 bg-n-blue-7 text-white px-4 py-3 rounded-lg"
            :style="{
              maxWidth:
                funnel.leads.total === 0
                  ? '100%'
                  : `${Math.max(20, (funnel.reservations.created / Math.max(1, funnel.leads.total)) * 100)}%`,
            }"
          >
            <span class="text-lg font-semibold">{{
              formatNumber(funnel.reservations.created)
            }}</span>
          </div>
          <div class="w-24 text-sm text-n-slate-11 text-right">
            {{ formatPct(funnel.conversion_rates.lead_to_any_reservation) }}
          </div>
        </div>
        <div class="flex items-center gap-4">
          <div class="w-32 text-sm text-n-slate-11">
            {{ $t('DIRECTORY_DASHBOARD.FUNNEL.STAGE_PAID') }}
          </div>
          <div
            class="flex-1 bg-n-teal-9 text-white px-4 py-3 rounded-lg"
            :style="{
              maxWidth:
                funnel.leads.total === 0
                  ? '100%'
                  : `${Math.max(20, (funnel.reservations.paid / Math.max(1, funnel.leads.total)) * 100)}%`,
            }"
          >
            <span class="text-lg font-semibold">{{
              formatNumber(funnel.reservations.paid)
            }}</span>
          </div>
          <div class="w-24 text-sm text-n-slate-11 text-right">
            {{ formatPct(funnel.conversion_rates.lead_to_paid_reservation) }}
          </div>
        </div>
      </div>
    </div>

    <div
      class="bg-n-solid-2 shadow outline-1 outline outline-n-container rounded-xl px-6 py-5"
    >
      <h3 class="text-base font-semibold m-0 mb-4">
        {{ $t('DIRECTORY_DASHBOARD.BENCHMARK.TITLE') }}
      </h3>
      <Spinner v-if="isLoadingBenchmark" />
      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="py-2 pr-4">
                {{ $t('DIRECTORY_DASHBOARD.BENCHMARK.COL_INBOX') }}
              </th>
              <th class="py-2 px-2 text-right">
                {{ $t('DIRECTORY_DASHBOARD.BENCHMARK.COL_LEADS') }}
              </th>
              <th class="py-2 px-2 text-right">
                {{ $t('DIRECTORY_DASHBOARD.BENCHMARK.COL_CREATED') }}
              </th>
              <th class="py-2 px-2 text-right">
                {{ $t('DIRECTORY_DASHBOARD.BENCHMARK.COL_PAID') }}
              </th>
              <th class="py-2 px-2 text-right">
                {{ $t('DIRECTORY_DASHBOARD.BENCHMARK.COL_RATE') }}
              </th>
              <th class="py-2 pl-2 text-right">
                {{ $t('DIRECTORY_DASHBOARD.BENCHMARK.COL_VS_BRAND') }}
              </th>
            </tr>
          </thead>
          <template v-for="group in benchmarkGrouped" :key="group.brand">
            <tbody>
              <tr class="bg-n-slate-3">
                <td colspan="6" class="py-2 px-2 font-semibold text-n-slate-12">
                  {{ group.brand }}
                  <span class="text-n-slate-11 font-normal text-xs ms-2">
                    ({{ $t('DIRECTORY_DASHBOARD.BENCHMARK.BRAND_AVG') }}
                    {{ formatPct(group.brandRate) }})
                  </span>
                </td>
              </tr>
              <tr
                v-for="row in group.rows"
                :key="row.inbox_id"
                class="border-b border-n-weak"
              >
                <td class="py-2 pr-4 text-n-slate-12">{{ row.inbox_name }}</td>
                <td class="py-2 px-2 text-right">
                  {{ formatNumber(row.leads_total) }}
                </td>
                <td class="py-2 px-2 text-right">
                  {{ formatNumber(row.reservations_created) }}
                </td>
                <td class="py-2 px-2 text-right">
                  {{ formatNumber(row.reservations_paid) }}
                </td>
                <td class="py-2 px-2 text-right font-medium">
                  {{ formatPct(row.conversion_rate) }}
                </td>
                <td class="py-2 pl-2 text-right">
                  <span
                    v-if="
                      variationFromBrand(row.conversion_rate, group.brandRate) >
                      0
                    "
                    class="text-n-teal-11"
                  >
                    +{{
                      variationFromBrand(row.conversion_rate, group.brandRate)
                    }}
                  </span>
                  <span
                    v-else-if="
                      variationFromBrand(row.conversion_rate, group.brandRate) <
                      0
                    "
                    class="text-n-ruby-11"
                  >
                    {{
                      variationFromBrand(row.conversion_rate, group.brandRate)
                    }}
                  </span>
                  <span v-else class="text-n-slate-11">—</span>
                </td>
              </tr>
            </tbody>
          </template>
        </table>
      </div>
    </div>
  </div>
</template>
