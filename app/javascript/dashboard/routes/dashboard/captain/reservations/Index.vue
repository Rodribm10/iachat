<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import NewReservationModal from './components/NewReservationModal.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const uiFlags = useMapGetter('captainReservations/getUIFlags');
const reservations = useMapGetter('captainReservations/getRecords');
const reservationsMeta = useMapGetter('captainReservations/getMeta');
const units = useMapGetter('captainUnits/getUnits');

const isFetching = computed(() => uiFlags.value.fetchingList);
const viewMode = ref('list');

const status = ref('all');
const q = ref('');
const dateFrom = ref('');
const dateTo = ref('');
const unitId = ref('');
const suite = ref('');
const sort = ref('');
const isFetchingRevenue = ref(false);
const showNewReservationModal = ref(false);

const emptyRevenue = () => ({
  summary: {
    total_revenue: 0,
    confirmed_count: 0,
    average_ticket: 0,
  },
  by_unit: [],
  by_suite: [],
});

const revenue = ref(emptyRevenue());
const isRevenueView = computed(() => viewMode.value === 'revenue');
const isPageFetching = computed(
  () => isFetching.value || isFetchingRevenue.value
);
const hasRevenueData = computed(
  () => Number(revenue.value.summary?.confirmed_count || 0) > 0
);

const statusOptions = computed(() => [
  { id: 'all', label: 'CAPTAIN_RESERVATIONS.FILTERS.STATUS_ALL' },
  { id: 'draft', label: 'CAPTAIN_RESERVATIONS.STATUS.DRAFT' },
  {
    id: 'pending_payment',
    label: 'CAPTAIN_RESERVATIONS.STATUS.PENDING_PAYMENT',
  },
  { id: 'confirmed', label: 'CAPTAIN_RESERVATIONS.STATUS.CONFIRMED' },
  { id: 'cancelled', label: 'CAPTAIN_RESERVATIONS.STATUS.CANCELLED' },
]);

const groupedReservations = computed(() => {
  const groups = {
    draft: [],
    pending_payment: [],
    confirmed: [],
    cancelled: [],
  };

  reservations.value.forEach(reservation => {
    const key = reservation.ui_status || 'draft';
    if (!groups[key]) groups[key] = [];
    groups[key].push(reservation);
  });

  return groups;
});

const readFiltersFromRoute = () => {
  const query = route.query || {};
  status.value = query.status || 'all';
  q.value = query.q || '';
  dateFrom.value = query.date_from || '';
  dateTo.value = query.date_to || '';
  unitId.value = query.unit_id || '';
  suite.value = query.suite || '';
  sort.value = query.sort || '';
  viewMode.value = ['kanban', 'revenue'].includes(query.view)
    ? query.view
    : 'list';
};

const buildQuery = (page = 1) => ({
  status: status.value,
  q: q.value || undefined,
  date_from: dateFrom.value || undefined,
  date_to: dateTo.value || undefined,
  unit_id: unitId.value || undefined,
  suite: suite.value || undefined,
  sort: sort.value || undefined,
  page,
  per_page: 25,
});

const buildRevenueQuery = () => ({
  q: q.value || undefined,
  date_from: dateFrom.value || undefined,
  date_to: dateTo.value || undefined,
  unit_id: unitId.value || undefined,
  suite: suite.value || undefined,
});

const syncRouteQuery = (page = 1) => {
  const query = {
    q: q.value || undefined,
    date_from: dateFrom.value || undefined,
    date_to: dateTo.value || undefined,
    unit_id: unitId.value || undefined,
    suite: suite.value || undefined,
    status: isRevenueView.value ? undefined : status.value,
    sort: isRevenueView.value ? undefined : sort.value || undefined,
    page: isRevenueView.value ? undefined : page,
    per_page: isRevenueView.value ? undefined : 25,
    view: viewMode.value === 'list' ? undefined : viewMode.value,
  };
  router.replace({ query });
};

const fetchReservations = (page = 1) => {
  syncRouteQuery(page);
  store.dispatch('captainReservations/get', buildQuery(page));
};

const fetchRevenue = async () => {
  syncRouteQuery();
  isFetchingRevenue.value = true;
  try {
    const data = await store.dispatch(
      'captainReservations/fetchRevenue',
      buildRevenueQuery()
    );
    revenue.value = data?.summary ? data : emptyRevenue();
  } catch (error) {
    revenue.value = emptyRevenue();
    useAlert(t('CAPTAIN_RESERVATIONS.REVENUE.API.ERROR'));
  } finally {
    isFetchingRevenue.value = false;
  }
};

const setViewMode = mode => {
  if (viewMode.value === mode) return;
  viewMode.value = mode;
  if (mode === 'revenue') {
    fetchRevenue();
    return;
  }
  fetchReservations(1);
};

const onPageChange = page => fetchReservations(page);

const applyFilters = () => {
  if (isRevenueView.value) {
    fetchRevenue();
    return;
  }
  fetchReservations(1);
};

const clearFilters = () => {
  status.value = 'all';
  q.value = '';
  dateFrom.value = '';
  dateTo.value = '';
  unitId.value = '';
  suite.value = '';
  sort.value = '';
  if (isRevenueView.value) {
    fetchRevenue();
    return;
  }
  fetchReservations(1);
};

const openConversation = reservation => {
  const conversationId =
    reservation.conversation_display_id || reservation.conversation_id;
  if (!conversationId) return;
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: conversationId,
    })
  );
  router.push(path);
};

const copyPix = async reservation => {
  const pix = reservation.pix_copy_paste;
  if (!pix) {
    useAlert(
      reservation.pix_reason === 'expired'
        ? t('CAPTAIN_RESERVATIONS.API.PIX_EXPIRED')
        : t('CAPTAIN_RESERVATIONS.API.PIX_NOT_GENERATED')
    );
    return;
  }

  try {
    await navigator.clipboard.writeText(pix);
    useAlert(t('CAPTAIN_RESERVATIONS.API.PIX_COPIED'));
  } catch (error) {
    useAlert(t('CAPTAIN_RESERVATIONS.API.PIX_COPY_FAILED'));
  }
};

const formatMoney = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    Number(value || 0)
  );

const formatDate = value =>
  value
    ? new Intl.DateTimeFormat('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      }).format(new Date(value))
    : '-';

const unitRevenueChart = computed(() => ({
  labels: revenue.value.by_unit.map(item => item.unit_name || '-'),
  datasets: [
    {
      label: t('CAPTAIN_RESERVATIONS.REVENUE.CHARTS.BY_UNIT'),
      backgroundColor: '#3b82f6',
      data: revenue.value.by_unit.map(item => Number(item.total_revenue || 0)),
    },
  ],
}));

const suiteRevenueChart = computed(() => ({
  labels: revenue.value.by_suite.map(item => item.suite_identifier || '-'),
  datasets: [
    {
      label: t('CAPTAIN_RESERVATIONS.REVENUE.CHARTS.BY_SUITE'),
      backgroundColor: '#10b981',
      data: revenue.value.by_suite.map(item => Number(item.total_revenue || 0)),
    },
  ],
}));

const statusColor = reservationStatus => {
  const colors = {
    draft: 'bg-n-slate-3 text-n-slate-11',
    pending_payment: 'bg-n-amber-3 text-n-amber-11',
    confirmed: 'bg-n-teal-3 text-n-teal-11',
    cancelled: 'bg-n-ruby-3 text-n-ruby-11',
  };
  return colors[reservationStatus] || 'bg-n-slate-3 text-n-slate-11';
};

onMounted(() => {
  readFiltersFromRoute();
  store.dispatch('captainUnits/get');
  if (isRevenueView.value) {
    fetchRevenue();
    return;
  }
  fetchReservations(Number(route.query.page) || 1);
});
</script>

<template>
  <PageLayout
    :header-title="$t('CAPTAIN_RESERVATIONS.HEADER')"
    :button-label="$t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.TITLE')"
    :feature-flag="FEATURE_FLAGS.CAPTAIN"
    :is-fetching="isPageFetching"
    :is-empty="isRevenueView ? !hasRevenueData : !reservations.length"
    :show-pagination-footer="
      !isPageFetching && viewMode === 'list' && !!reservations.length
    "
    :total-count="
      isRevenueView
        ? revenue.summary.confirmed_count
        : reservationsMeta.totalCount
    "
    :current-page="isRevenueView ? 1 : reservationsMeta.page"
    :show-know-more="false"
    :show-assistant-switcher="false"
    @click="showNewReservationModal = true"
    @update:current-page="onPageChange"
  >
    <template #controls>
      <div
        class="grid grid-cols-1 gap-3 p-4 mb-4 rounded-xl bg-n-surface-2 md:grid-cols-7"
      >
        <div class="md:col-span-2">
          <Input
            v-model="q"
            :label="$t('CAPTAIN_RESERVATIONS.FILTERS.SEARCH')"
          />
        </div>
        <div v-if="!isRevenueView">
          <label class="text-sm text-n-slate-11">{{
            $t('CAPTAIN_RESERVATIONS.FILTERS.STATUS')
          }}</label>
          <select
            v-model="status"
            class="w-full px-2 py-2 mt-1 border rounded-lg bg-n-background border-n-weak"
          >
            <option
              v-for="option in statusOptions"
              :key="option.id"
              :value="option.id"
            >
              {{ $t(option.label) }}
            </option>
          </select>
        </div>
        <div>
          <label class="text-sm text-n-slate-11">{{
            $t('CAPTAIN_RESERVATIONS.FILTERS.UNIT')
          }}</label>
          <select
            v-model="unitId"
            class="w-full px-2 py-2 mt-1 border rounded-lg bg-n-background border-n-weak"
          >
            <option value="">
              {{ $t('CAPTAIN_RESERVATIONS.FILTERS.UNIT_ALL') }}
            </option>
            <option v-for="unit in units" :key="unit.id" :value="unit.id">
              {{ unit.name }}
            </option>
          </select>
        </div>
        <div>
          <Input
            v-model="suite"
            :label="$t('CAPTAIN_RESERVATIONS.FILTERS.SUITE')"
          />
        </div>
        <div>
          <Input
            v-model="dateFrom"
            type="date"
            :label="$t('CAPTAIN_RESERVATIONS.FILTERS.DATE_FROM')"
          />
        </div>
        <div>
          <Input
            v-model="dateTo"
            type="date"
            :label="$t('CAPTAIN_RESERVATIONS.FILTERS.DATE_TO')"
          />
        </div>
        <div>
          <label class="text-sm text-n-slate-11">{{
            $t('CAPTAIN_RESERVATIONS.FILTERS.SORT')
          }}</label>
          <select
            v-model="sort"
            :disabled="isRevenueView"
            class="w-full px-2 py-2 mt-1 border rounded-lg bg-n-background border-n-weak"
          >
            <option value="">
              {{ $t('CAPTAIN_RESERVATIONS.FILTERS.SORT_DEFAULT') }}
            </option>
            <option value="check_in_at">
              {{ $t('CAPTAIN_RESERVATIONS.FILTERS.SORT_CHECK_IN') }}
            </option>
            <option value="updated_at">
              {{ $t('CAPTAIN_RESERVATIONS.FILTERS.SORT_UPDATED') }}
            </option>
            <option value="created_at">
              {{ $t('CAPTAIN_RESERVATIONS.FILTERS.SORT_CREATED') }}
            </option>
          </select>
        </div>
      </div>
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
          <Button
            :label="$t('CAPTAIN_RESERVATIONS.VIEW.LIST')"
            :variant="viewMode === 'list' ? 'primary' : 'outline'"
            size="sm"
            @click="setViewMode('list')"
          />
          <Button
            :label="$t('CAPTAIN_RESERVATIONS.VIEW.KANBAN')"
            :variant="viewMode === 'kanban' ? 'primary' : 'outline'"
            size="sm"
            @click="setViewMode('kanban')"
          />
          <Button
            :label="$t('CAPTAIN_RESERVATIONS.VIEW.REVENUE')"
            :variant="viewMode === 'revenue' ? 'primary' : 'outline'"
            size="sm"
            @click="setViewMode('revenue')"
          />
        </div>
        <div class="flex items-center gap-2">
          <Button
            :label="$t('CAPTAIN_RESERVATIONS.FILTERS.CLEAR')"
            variant="ghost"
            size="sm"
            @click="clearFilters"
          />
          <Button
            :label="$t('CAPTAIN_RESERVATIONS.FILTERS.APPLY')"
            size="sm"
            @click="applyFilters"
          />
        </div>
      </div>
    </template>

    <template #emptyState>
      <div class="py-16 text-center text-n-slate-11">
        {{ $t('CAPTAIN_RESERVATIONS.EMPTY') }}
      </div>
    </template>

    <template #body>
      <div v-if="isPageFetching" class="flex justify-center py-12">
        <Spinner />
      </div>

      <div
        v-else-if="viewMode === 'list'"
        class="overflow-x-auto border rounded-xl border-n-weak"
      >
        <table class="w-full text-sm">
          <thead class="bg-n-surface-2 text-n-slate-11">
            <tr>
              <th class="px-3 py-2 text-left">
                {{ $t('CAPTAIN_RESERVATIONS.TABLE.CUSTOMER') }}
              </th>
              <th class="px-3 py-2 text-left">
                {{ $t('CAPTAIN_RESERVATIONS.TABLE.UNIT') }}
              </th>
              <th class="px-3 py-2 text-left">
                {{ $t('CAPTAIN_RESERVATIONS.TABLE.SUITE') }}
              </th>
              <th class="px-3 py-2 text-left">
                {{ $t('CAPTAIN_RESERVATIONS.TABLE.CHECK_IN') }}
              </th>
              <th class="px-3 py-2 text-left">
                {{ $t('CAPTAIN_RESERVATIONS.TABLE.AMOUNT') }}
              </th>
              <th class="px-3 py-2 text-left">
                {{ $t('CAPTAIN_RESERVATIONS.TABLE.STATUS') }}
              </th>
              <th class="px-3 py-2 text-left">
                {{ $t('CAPTAIN_RESERVATIONS.TABLE.UPDATED_AT') }}
              </th>
              <th class="px-3 py-2 text-left">
                {{ $t('CAPTAIN_RESERVATIONS.TABLE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="reservation in reservations"
              :key="reservation.id"
              class="border-t border-n-weak"
            >
              <td class="px-3 py-2">
                <p class="font-medium text-n-slate-12">
                  {{ reservation.customer_name || '-' }}
                </p>
                <p class="text-xs text-n-slate-11">
                  {{
                    reservation.customer_phone ||
                    reservation.customer_cpf ||
                    '-'
                  }}
                </p>
              </td>
              <td class="px-3 py-2">{{ reservation.unit_name || '-' }}</td>
              <td class="px-3 py-2">
                {{ reservation.suite_identifier || '-' }}
              </td>
              <td class="px-3 py-2">
                {{ formatDate(reservation.check_in_at) }}
              </td>
              <td class="px-3 py-2">{{ formatMoney(reservation.amount) }}</td>
              <td class="px-3 py-2">
                <span
                  class="px-2 py-1 text-xs rounded-full font-medium"
                  :class="statusColor(reservation.ui_status)"
                >
                  {{ reservation.status_label }}
                </span>
              </td>
              <td class="px-3 py-2">
                {{ formatDate(reservation.updated_at) }}
              </td>
              <td class="px-3 py-2">
                <div class="flex items-center gap-2">
                  <Button
                    size="xs"
                    variant="outline"
                    :label="
                      $t('CAPTAIN_RESERVATIONS.ACTIONS.OPEN_CONVERSATION')
                    "
                    @click="openConversation(reservation)"
                  />
                  <Button
                    size="xs"
                    variant="ghost"
                    :label="$t('CAPTAIN_RESERVATIONS.ACTIONS.COPY_PIX')"
                    @click="copyPix(reservation)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-else-if="viewMode === 'revenue'" class="space-y-4">
        <div
          class="px-3 py-2 text-xs rounded-lg bg-n-surface-2 text-n-slate-11"
        >
          {{ $t('CAPTAIN_RESERVATIONS.REVENUE.ONLY_CONFIRMED') }}
        </div>
        <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
          <div class="p-4 border rounded-xl border-n-weak bg-n-background">
            <p class="text-sm text-n-slate-11">
              {{ $t('CAPTAIN_RESERVATIONS.REVENUE.SUMMARY.TOTAL_REVENUE') }}
            </p>
            <p class="mt-1 text-2xl font-semibold text-n-slate-12">
              {{ formatMoney(revenue.summary.total_revenue) }}
            </p>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-background">
            <p class="text-sm text-n-slate-11">
              {{ $t('CAPTAIN_RESERVATIONS.REVENUE.SUMMARY.CONFIRMED_COUNT') }}
            </p>
            <p class="mt-1 text-2xl font-semibold text-n-slate-12">
              {{ revenue.summary.confirmed_count || 0 }}
            </p>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-background">
            <p class="text-sm text-n-slate-11">
              {{ $t('CAPTAIN_RESERVATIONS.REVENUE.SUMMARY.AVERAGE_TICKET') }}
            </p>
            <p class="mt-1 text-2xl font-semibold text-n-slate-12">
              {{ formatMoney(revenue.summary.average_ticket) }}
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div class="p-4 border rounded-xl border-n-weak bg-n-background">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ $t('CAPTAIN_RESERVATIONS.REVENUE.CHARTS.BY_UNIT') }}
            </h3>
            <div class="h-64 mt-3">
              <BarChart :collection="unitRevenueChart" />
            </div>
          </div>
          <div class="p-4 border rounded-xl border-n-weak bg-n-background">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ $t('CAPTAIN_RESERVATIONS.REVENUE.CHARTS.BY_SUITE') }}
            </h3>
            <div class="h-64 mt-3">
              <BarChart :collection="suiteRevenueChart" />
            </div>
          </div>
        </div>
      </div>

      <div v-else class="grid grid-cols-1 gap-4 lg:grid-cols-4">
        <div
          v-for="column in [
            'draft',
            'pending_payment',
            'confirmed',
            'cancelled',
          ]"
          :key="column"
          class="p-3 border rounded-xl bg-n-surface-2 border-n-weak"
        >
          <h3 class="mb-3 text-sm font-medium text-n-slate-12">
            {{ $t(`CAPTAIN_RESERVATIONS.STATUS.${column.toUpperCase()}`) }}
          </h3>
          <div class="flex flex-col gap-2">
            <div
              v-for="reservation in groupedReservations[column]"
              :key="reservation.id"
              class="p-3 border rounded-lg bg-n-background border-n-weak"
            >
              <p class="text-sm font-medium text-n-slate-12">
                {{ reservation.customer_name || '-' }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ reservation.suite_identifier || '-' }}
              </p>
              <p class="mt-2 text-xs text-n-slate-11">
                {{ formatDate(reservation.check_in_at) }} •
                {{ formatMoney(reservation.amount) }}
              </p>
              <div class="flex gap-2 mt-3">
                <Button
                  size="xs"
                  variant="outline"
                  :label="$t('CAPTAIN_RESERVATIONS.ACTIONS.OPEN_CONVERSATION')"
                  @click="openConversation(reservation)"
                />
                <Button
                  size="xs"
                  variant="ghost"
                  :label="$t('CAPTAIN_RESERVATIONS.ACTIONS.COPY_PIX')"
                  @click="copyPix(reservation)"
                />
              </div>
            </div>
            <p
              v-if="!groupedReservations[column].length"
              class="text-xs text-n-slate-11"
            >
              {{ $t('CAPTAIN_RESERVATIONS.KANBAN.EMPTY_COLUMN') }}
            </p>
          </div>
        </div>
      </div>
    </template>
  </PageLayout>
  <NewReservationModal
    v-if="showNewReservationModal"
    @close="showNewReservationModal = false"
    @success="fetchReservations(1)"
  />
</template>
