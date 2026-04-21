<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
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
const showAdvancedFilters = ref(false);

// Tick reativo — força pixCountdown a recalcular a cada 30s
const tickNow = ref(Date.now());
let tickInterval = null;
let refreshInterval = null;
const actionMenuOpenFor = ref(null);
const actionLoading = ref(null);

const emptyRevenue = () => ({
  summary: { total_revenue: 0, confirmed_count: 0, average_ticket: 0 },
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

const STATUS_PILLS = [
  { id: 'all', labelKey: 'CAPTAIN_RESERVATIONS.PILLS.ALL', tone: 'slate' },
  { id: 'draft', labelKey: 'CAPTAIN_RESERVATIONS.PILLS.DRAFT', tone: 'slate' },
  {
    id: 'pending_payment',
    labelKey: 'CAPTAIN_RESERVATIONS.PILLS.PENDING_PAYMENT',
    tone: 'amber',
  },
  {
    id: 'confirmed',
    labelKey: 'CAPTAIN_RESERVATIONS.PILLS.CONFIRMED',
    tone: 'teal',
  },
  {
    id: 'cancelled',
    labelKey: 'CAPTAIN_RESERVATIONS.PILLS.CANCELLED',
    tone: 'ruby',
  },
];

const QUICK_DATES = [
  { id: 'today', labelKey: 'CAPTAIN_RESERVATIONS.QUICK_DATE.TODAY' },
  { id: 'tomorrow', labelKey: 'CAPTAIN_RESERVATIONS.QUICK_DATE.TOMORROW' },
  { id: 'week', labelKey: 'CAPTAIN_RESERVATIONS.QUICK_DATE.WEEK' },
  { id: 'all', labelKey: 'CAPTAIN_RESERVATIONS.QUICK_DATE.ALL' },
];

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

const statusCounts = computed(() => {
  const counts = {
    all: reservations.value.length,
    draft: 0,
    pending_payment: 0,
    confirmed: 0,
    cancelled: 0,
  };
  reservations.value.forEach(r => {
    const key = r.ui_status || 'draft';
    if (counts[key] !== undefined) counts[key] += 1;
  });
  return counts;
});

const todayRevenue = computed(() => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return reservations.value
    .filter(r => r.ui_status === 'confirmed')
    .filter(r => {
      if (!r.check_in_at) return false;
      const d = new Date(r.check_in_at);
      return d >= today && d < new Date(today.getTime() + 86400000);
    })
    .reduce((sum, r) => sum + Number(r.amount || 0), 0);
});

const pendingPixCount = computed(() => statusCounts.value.pending_payment);
const confirmedTodayCount = computed(() => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return reservations.value.filter(r => {
    if (r.ui_status !== 'confirmed' || !r.check_in_at) return false;
    const d = new Date(r.check_in_at);
    return d >= today && d < new Date(today.getTime() + 86400000);
  }).length;
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

const setStatusPill = id => {
  if (status.value === id) return;
  status.value = id;
  fetchReservations(1);
};

const setUnitPill = id => {
  const next = String(id || '');
  if (unitId.value === next) return;
  unitId.value = next;
  fetchReservations(1);
};

const setQuickDate = preset => {
  const now = new Date();
  const iso = d => d.toISOString().slice(0, 10);
  if (preset === 'today') {
    dateFrom.value = iso(now);
    dateTo.value = iso(now);
  } else if (preset === 'tomorrow') {
    const tomorrow = new Date(now.getTime() + 86400000);
    dateFrom.value = iso(tomorrow);
    dateTo.value = iso(tomorrow);
  } else if (preset === 'week') {
    const in7 = new Date(now.getTime() + 7 * 86400000);
    dateFrom.value = iso(now);
    dateTo.value = iso(in7);
  } else {
    dateFrom.value = '';
    dateTo.value = '';
  }
  fetchReservations(1);
};

const isQuickDateActive = preset => {
  if (preset === 'all') return !dateFrom.value && !dateTo.value;
  const iso = d => d.toISOString().slice(0, 10);
  const now = new Date();
  if (preset === 'today') {
    const today = iso(now);
    return dateFrom.value === today && dateTo.value === today;
  }
  if (preset === 'tomorrow') {
    const tomorrow = iso(new Date(now.getTime() + 86400000));
    return dateFrom.value === tomorrow && dateTo.value === tomorrow;
  }
  if (preset === 'week') {
    const in7 = iso(new Date(now.getTime() + 7 * 86400000));
    return dateFrom.value === iso(now) && dateTo.value === in7;
  }
  return false;
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
    conversationUrl({ accountId: route.params.accountId, id: conversationId })
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

const formatCheckIn = value => {
  if (!value) return '-';
  const d = new Date(value);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const target = new Date(d);
  target.setHours(0, 0, 0, 0);
  const diffDays = Math.round((target - today) / 86400000);
  const hour = d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
  if (diffDays === 0) return `${t('CAPTAIN_RESERVATIONS.CARD.TODAY')} ${hour}`;
  if (diffDays === 1)
    return `${t('CAPTAIN_RESERVATIONS.CARD.TOMORROW')} ${hour}`;
  if (diffDays === -1)
    return `${t('CAPTAIN_RESERVATIONS.CARD.YESTERDAY')} ${hour}`;
  const weekday = d.toLocaleDateString('pt-BR', { weekday: 'short' });
  const day = d.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });
  return `${weekday} ${day} ${hour}`;
};

const pixCountdown = reservation => {
  const expires = reservation.pix_expires_at;
  if (!expires) return null;
  // depender de tickNow força recomputação
  const diff = new Date(expires).getTime() - tickNow.value;
  if (diff <= 0)
    return { label: t('CAPTAIN_RESERVATIONS.CARD.PIX_EXPIRED'), expired: true };
  const mins = Math.floor(diff / 60000);
  if (mins < 60)
    return {
      label: t('CAPTAIN_RESERVATIONS.CARD.PIX_EXPIRES_IN_MIN', {
        minutes: mins,
      }),
      expired: false,
    };
  const hours = Math.floor(mins / 60);
  return {
    label: t('CAPTAIN_RESERVATIONS.CARD.PIX_EXPIRES_IN_HR', { hours }),
    expired: false,
  };
};

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

const statusBadgeClass = reservationStatus => {
  const map = {
    draft: 'bg-n-slate-3 text-n-slate-11',
    pending_payment: 'bg-n-amber-3 text-n-amber-11',
    confirmed: 'bg-n-teal-3 text-n-teal-11',
    cancelled: 'bg-n-ruby-3 text-n-ruby-11',
  };
  return map[reservationStatus] || 'bg-n-slate-3 text-n-slate-11';
};

const statusBarClass = reservationStatus => {
  const map = {
    draft: 'bg-n-slate-7',
    pending_payment: 'bg-n-amber-9',
    confirmed: 'bg-n-teal-9',
    cancelled: 'bg-n-ruby-9',
  };
  return map[reservationStatus] || 'bg-n-slate-7';
};

const pillClass = (pill, active) => {
  const toneActive = {
    slate: 'bg-n-slate-12 text-white border-n-slate-12',
    amber: 'bg-n-amber-9 text-white border-n-amber-9',
    teal: 'bg-n-teal-9 text-white border-n-teal-9',
    ruby: 'bg-n-ruby-9 text-white border-n-ruby-9',
  };
  return active
    ? toneActive[pill.tone]
    : 'bg-n-background text-n-slate-11 border-n-weak hover:bg-n-surface-2';
};

// Ações: reenviar PIX / marcar como pago / cancelar
const regeneratePix = async reservation => {
  if (actionLoading.value) return;
  actionLoading.value = reservation.id;
  try {
    await store.dispatch('captainReservations/regeneratePix', reservation.id);
    useAlert(t('CAPTAIN_RESERVATIONS.ACTIONS.PIX_REGENERATED'));
    fetchReservations(reservationsMeta.value.page || 1);
  } catch (error) {
    useAlert(t('CAPTAIN_RESERVATIONS.ACTIONS.PIX_REGENERATE_FAILED'));
  } finally {
    actionLoading.value = null;
    actionMenuOpenFor.value = null;
  }
};

const markAsPaid = async reservation => {
  if (actionLoading.value) return;
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CAPTAIN_RESERVATIONS.ACTIONS.MARK_AS_PAID_CONFIRM'))) {
    return;
  }
  actionLoading.value = reservation.id;
  try {
    await store.dispatch('captainReservations/markAsPaid', {
      id: reservation.id,
    });
    useAlert(t('CAPTAIN_RESERVATIONS.ACTIONS.MARKED_AS_PAID'));
    fetchReservations(reservationsMeta.value.page || 1);
  } catch (error) {
    useAlert(t('CAPTAIN_RESERVATIONS.ACTIONS.MARK_AS_PAID_FAILED'));
  } finally {
    actionLoading.value = null;
    actionMenuOpenFor.value = null;
  }
};

const cancelReservation = async reservation => {
  if (actionLoading.value) return;
  // eslint-disable-next-line no-alert
  const reason = window.prompt(
    t('CAPTAIN_RESERVATIONS.ACTIONS.CANCEL_REASON_PROMPT'),
    ''
  );
  if (reason === null) return; // cancelou o prompt
  actionLoading.value = reservation.id;
  try {
    await store.dispatch('captainReservations/cancel', {
      id: reservation.id,
      reason,
    });
    useAlert(t('CAPTAIN_RESERVATIONS.ACTIONS.CANCELLED'));
    fetchReservations(reservationsMeta.value.page || 1);
  } catch (error) {
    useAlert(t('CAPTAIN_RESERVATIONS.ACTIONS.CANCEL_FAILED'));
  } finally {
    actionLoading.value = null;
    actionMenuOpenFor.value = null;
  }
};

const toggleActionMenu = reservationId => {
  actionMenuOpenFor.value =
    actionMenuOpenFor.value === reservationId ? null : reservationId;
};

const hasPendingReservations = computed(() =>
  reservations.value.some(r => r.ui_status === 'pending_payment')
);

// Auto-refresh: 30s quando tem pendente e aba visível
const startAutoRefresh = () => {
  if (refreshInterval) return;
  refreshInterval = setInterval(() => {
    if (document.hidden) return;
    if (!hasPendingReservations.value) return;
    if (isPageFetching.value) return;
    if (viewMode.value !== 'list') return;
    fetchReservations(reservationsMeta.value.page || 1);
  }, 30000);
};

const startTick = () => {
  if (tickInterval) return;
  tickInterval = setInterval(() => {
    tickNow.value = Date.now();
  }, 30000);
};

onMounted(() => {
  readFiltersFromRoute();
  store.dispatch('captainUnits/get');
  if (isRevenueView.value) {
    fetchRevenue();
  } else {
    fetchReservations(Number(route.query.page) || 1);
  }
  startTick();
  startAutoRefresh();
});

onBeforeUnmount(() => {
  if (tickInterval) clearInterval(tickInterval);
  if (refreshInterval) clearInterval(refreshInterval);
  tickInterval = null;
  refreshInterval = null;
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
      <!-- KPI strip -->
      <div class="grid grid-cols-2 gap-3 mb-4 md:grid-cols-4">
        <div class="p-3 border rounded-xl bg-n-background border-n-weak">
          <p class="text-xs text-n-slate-11">
            {{ $t('CAPTAIN_RESERVATIONS.KPI.TOTAL') }}
          </p>
          <p class="mt-1 text-xl font-semibold text-n-slate-12">
            {{ reservationsMeta.totalCount || reservations.length || 0 }}
          </p>
        </div>
        <div
          class="p-3 border rounded-xl bg-n-amber-2 border-n-amber-6"
          :class="{ 'ring-2 ring-n-amber-9': pendingPixCount > 0 }"
        >
          <p class="text-xs text-n-amber-11">
            {{ $t('CAPTAIN_RESERVATIONS.KPI.PENDING_PIX') }}
          </p>
          <p class="mt-1 text-xl font-semibold text-n-amber-12">
            {{ pendingPixCount }}
          </p>
        </div>
        <div class="p-3 border rounded-xl bg-n-teal-2 border-n-teal-6">
          <p class="text-xs text-n-teal-11">
            {{ $t('CAPTAIN_RESERVATIONS.KPI.CHECKIN_TODAY') }}
          </p>
          <p class="mt-1 text-xl font-semibold text-n-teal-12">
            {{ confirmedTodayCount }}
          </p>
        </div>
        <div class="p-3 border rounded-xl bg-n-background border-n-weak">
          <p class="text-xs text-n-slate-11">
            {{ $t('CAPTAIN_RESERVATIONS.KPI.REVENUE_TODAY') }}
          </p>
          <p class="mt-1 text-xl font-semibold text-n-slate-12">
            {{ formatMoney(todayRevenue) }}
          </p>
        </div>
      </div>

      <!-- Unit pills (uma caixa de entrada = uma unidade) -->
      <div v-if="units.length > 1" class="flex flex-wrap gap-2 mb-3">
        <button
          type="button"
          class="px-3 py-1.5 text-xs font-medium border rounded-full transition-colors"
          :class="
            !unitId
              ? 'bg-n-slate-12 text-white border-n-slate-12'
              : 'bg-n-background text-n-slate-11 border-n-weak hover:bg-n-surface-2'
          "
          @click="setUnitPill('')"
        >
          {{ $t('CAPTAIN_RESERVATIONS.FILTERS.UNIT_ALL') }}
        </button>
        <button
          v-for="unit in units"
          :key="unit.id"
          type="button"
          class="px-3 py-1.5 text-xs font-medium border rounded-full transition-colors"
          :class="
            String(unitId) === String(unit.id)
              ? 'bg-n-slate-12 text-white border-n-slate-12'
              : 'bg-n-background text-n-slate-11 border-n-weak hover:bg-n-surface-2'
          "
          @click="setUnitPill(unit.id)"
        >
          {{ unit.name }}
        </button>
      </div>

      <!-- Status pills -->
      <div class="flex flex-wrap gap-2 mb-3">
        <button
          v-for="pill in STATUS_PILLS"
          :key="pill.id"
          type="button"
          class="px-3 py-1.5 text-xs font-medium border rounded-full transition-colors"
          :class="pillClass(pill, status === pill.id)"
          @click="setStatusPill(pill.id)"
        >
          {{ $t(pill.labelKey) }}
          <span
            v-if="pill.id !== 'all' && statusCounts[pill.id]"
            class="ml-1 opacity-80"
          >
            · {{ statusCounts[pill.id] }}
          </span>
        </button>
      </div>

      <!-- Quick date + search + toggle -->
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <div class="flex gap-1">
          <button
            v-for="preset in QUICK_DATES"
            :key="preset.id"
            type="button"
            class="px-3 py-1.5 text-xs font-medium border rounded-lg transition-colors"
            :class="
              isQuickDateActive(preset.id)
                ? 'bg-n-slate-12 text-white border-n-slate-12'
                : 'bg-n-background text-n-slate-11 border-n-weak hover:bg-n-surface-2'
            "
            @click="setQuickDate(preset.id)"
          >
            {{ $t(preset.labelKey) }}
          </button>
        </div>
        <div class="flex-1 min-w-[200px]">
          <Input
            v-model="q"
            :placeholder="$t('CAPTAIN_RESERVATIONS.FILTERS.SEARCH')"
            @keyup.enter="applyFilters"
          />
        </div>
        <Button
          :label="
            showAdvancedFilters
              ? $t('CAPTAIN_RESERVATIONS.FILTERS.HIDE')
              : $t('CAPTAIN_RESERVATIONS.FILTERS.APPLY')
          "
          size="sm"
          variant="outline"
          @click="showAdvancedFilters = !showAdvancedFilters"
        />
        <Button
          :label="$t('CAPTAIN_RESERVATIONS.FILTERS.CLEAR')"
          size="sm"
          variant="ghost"
          @click="clearFilters"
        />
      </div>

      <!-- Advanced filters (collapsible) -->
      <div
        v-if="showAdvancedFilters"
        class="grid grid-cols-1 gap-3 p-4 mb-4 rounded-xl bg-n-surface-2 md:grid-cols-5"
      >
        <div>
          <label class="text-xs text-n-slate-11">{{
            $t('CAPTAIN_RESERVATIONS.FILTERS.UNIT')
          }}</label>
          <select
            v-model="unitId"
            class="w-full px-2 py-2 mt-1 text-sm border rounded-lg bg-n-background border-n-weak"
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
          <label class="text-xs text-n-slate-11">{{
            $t('CAPTAIN_RESERVATIONS.FILTERS.SORT')
          }}</label>
          <select
            v-model="sort"
            :disabled="isRevenueView"
            class="w-full px-2 py-2 mt-1 text-sm border rounded-lg bg-n-background border-n-weak"
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
        <div class="md:col-span-5">
          <Button
            :label="$t('CAPTAIN_RESERVATIONS.FILTERS.APPLY')"
            size="sm"
            @click="applyFilters"
          />
        </div>
      </div>

      <!-- View mode toggle -->
      <div class="flex items-center justify-end gap-2 mb-4">
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

      <!-- CARDS GRID (replaces table) -->
      <div
        v-else-if="viewMode === 'list'"
        class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3"
      >
        <article
          v-for="reservation in reservations"
          :key="reservation.id"
          class="relative flex flex-col p-4 pl-5 overflow-hidden transition-all border rounded-xl bg-n-background border-n-weak hover:border-n-slate-7 hover:shadow-md"
        >
          <!-- Colored status bar (left) -->
          <span
            class="absolute top-0 bottom-0 left-0 w-1"
            :class="statusBarClass(reservation.ui_status)"
          />

          <!-- Header row -->
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <h3
                class="text-base font-semibold truncate text-n-slate-12"
                :title="reservation.customer_name"
              >
                {{ reservation.customer_name || '—' }}
              </h3>
              <p class="mt-0.5 text-xs text-n-slate-11 truncate">
                {{
                  reservation.customer_phone || reservation.customer_cpf || '—'
                }}
              </p>
            </div>
            <span
              class="shrink-0 px-2 py-1 text-[10px] uppercase tracking-wide rounded-full font-semibold"
              :class="statusBadgeClass(reservation.ui_status)"
            >
              {{ reservation.status_label }}
            </span>
          </div>

          <!-- Suite + unit -->
          <div class="mt-3 space-y-1">
            <p class="text-sm font-medium text-n-slate-12">
              {{ reservation.suite_identifier || '—' }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ reservation.unit_name || '—' }}
            </p>
          </div>

          <!-- Check-in + amount -->
          <div
            class="flex items-end justify-between gap-2 mt-3 pt-3 border-t border-n-weak"
          >
            <div>
              <p class="text-[10px] uppercase text-n-slate-10">
                {{ $t('CAPTAIN_RESERVATIONS.CARD.CHECK_IN') }}
              </p>
              <p class="text-sm font-medium text-n-slate-12">
                {{ formatCheckIn(reservation.check_in_at) }}
              </p>
            </div>
            <div class="text-right">
              <p class="text-[10px] uppercase text-n-slate-10">
                {{ $t('CAPTAIN_RESERVATIONS.CARD.AMOUNT') }}
              </p>
              <p class="text-base font-semibold text-n-slate-12">
                {{ formatMoney(reservation.amount) }}
              </p>
            </div>
          </div>

          <!-- PIX countdown (only pending) -->
          <div
            v-if="
              reservation.ui_status === 'pending_payment' &&
              pixCountdown(reservation)
            "
            class="mt-2 px-2 py-1 text-[11px] rounded-md text-center"
            :class="
              pixCountdown(reservation).expired
                ? 'bg-n-ruby-3 text-n-ruby-11'
                : 'bg-n-amber-3 text-n-amber-11'
            "
          >
            {{ '⏱ ' + pixCountdown(reservation).label }}
          </div>

          <!-- Actions -->
          <div class="relative flex gap-2 mt-3">
            <Button
              size="xs"
              variant="outline"
              class="flex-1"
              :label="$t('CAPTAIN_RESERVATIONS.ACTIONS.OPEN_CONVERSATION')"
              @click="openConversation(reservation)"
            />
            <Button
              size="xs"
              variant="ghost"
              :label="$t('CAPTAIN_RESERVATIONS.ACTIONS.COPY_PIX')"
              @click="copyPix(reservation)"
            />
            <Button
              size="xs"
              variant="ghost"
              :label="$t('CAPTAIN_RESERVATIONS.ACTIONS.MORE')"
              :disabled="actionLoading === reservation.id"
              @click="toggleActionMenu(reservation.id)"
            />
            <div
              v-if="actionMenuOpenFor === reservation.id"
              class="absolute right-0 z-10 w-56 mt-1 overflow-hidden border rounded-lg shadow-lg top-full bg-n-background border-n-weak"
            >
              <button
                v-if="reservation.ui_status === 'pending_payment'"
                type="button"
                class="block w-full px-3 py-2 text-xs text-left text-n-slate-12 hover:bg-n-surface-2"
                :disabled="actionLoading === reservation.id"
                @click="regeneratePix(reservation)"
              >
                {{ $t('CAPTAIN_RESERVATIONS.ACTIONS.REGENERATE_PIX') }}
              </button>
              <button
                v-if="
                  reservation.ui_status === 'pending_payment' ||
                  reservation.ui_status === 'draft'
                "
                type="button"
                class="block w-full px-3 py-2 text-xs text-left text-n-slate-12 hover:bg-n-surface-2"
                :disabled="actionLoading === reservation.id"
                @click="markAsPaid(reservation)"
              >
                {{ $t('CAPTAIN_RESERVATIONS.ACTIONS.MARK_AS_PAID') }}
              </button>
              <button
                v-if="reservation.ui_status !== 'cancelled'"
                type="button"
                class="block w-full px-3 py-2 text-xs text-left text-n-ruby-11 hover:bg-n-surface-2"
                :disabled="actionLoading === reservation.id"
                @click="cancelReservation(reservation)"
              >
                {{ $t('CAPTAIN_RESERVATIONS.ACTIONS.CANCEL') }}
              </button>
            </div>
          </div>
        </article>
      </div>

      <!-- REVENUE view (unchanged logic) -->
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

      <!-- KANBAN view (same cards) -->
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
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-sm font-medium text-n-slate-12">
              {{ $t(`CAPTAIN_RESERVATIONS.STATUS.${column.toUpperCase()}`) }}
            </h3>
            <span class="text-xs text-n-slate-11">
              {{ groupedReservations[column].length }}
            </span>
          </div>
          <div class="flex flex-col gap-2">
            <article
              v-for="reservation in groupedReservations[column]"
              :key="reservation.id"
              class="relative p-3 pl-4 overflow-hidden border rounded-lg bg-n-background border-n-weak"
            >
              <span
                class="absolute top-0 bottom-0 left-0 w-1"
                :class="statusBarClass(reservation.ui_status)"
              />
              <p class="text-sm font-semibold text-n-slate-12 truncate">
                {{ reservation.customer_name || '—' }}
              </p>
              <p class="text-xs text-n-slate-11 truncate">
                {{ reservation.suite_identifier || '—' }} ·
                {{ reservation.unit_name || '—' }}
              </p>
              <p class="mt-2 text-xs text-n-slate-11">
                {{ formatCheckIn(reservation.check_in_at) }} ·
                <span class="font-medium text-n-slate-12">{{
                  formatMoney(reservation.amount)
                }}</span>
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
            </article>
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
