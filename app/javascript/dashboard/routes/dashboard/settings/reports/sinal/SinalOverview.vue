<script setup>
// Réplica nativa da página Overview do Sinal, alimentada pelos dados da conta.
import { ref, computed, onMounted, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRouter, useRoute } from 'vue-router';
import SinalReportsAPI from 'dashboard/api/sinalReports';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SinalShell from './SinalShell.vue';
import HardCard from './HardCard.vue';
import WordCloud from './WordCloud.vue';
import AreaCompareChart from './AreaCompareChart.vue';
import {
  timeAgo,
  formatMinutes,
  formatNumber,
  dateInputValue,
  monthInputValue,
  monthEndDate,
} from './helpers';

const router = useRouter();
const route = useRoute();
const inboxes = useMapGetter('inboxes/getInboxes');

const PERIODS = [7, 14, 30];
const days = ref(7);
const selectedInboxId = ref('all');
const isLoading = ref(true);
const overview = ref(null);

const operationPeriod = ref('today');
const operationDay = ref(dateInputValue());
const operationMonth = ref(monthInputValue());
const operationCustomStart = ref(dateInputValue());
const operationCustomEnd = ref(dateInputValue());
const agents = ref([]);

const inboxParam = computed(() =>
  selectedInboxId.value === 'all' ? undefined : selectedInboxId.value
);

const selectedInbox = computed(() =>
  inboxes.value.find(
    inbox => String(inbox.id) === String(selectedInboxId.value)
  )
);

const epochRange = computed(() => {
  const until = Math.floor(Date.now() / 1000);
  return { since: until - days.value * 86400, until };
});

const operationRange = computed(() => {
  const dayStart = date => Math.floor(new Date(`${date}T00:00:00`) / 1000);
  const dayEnd = date => Math.floor(new Date(`${date}T23:59:59`) / 1000);
  const today = dateInputValue();
  if (operationPeriod.value === 'today')
    return { since: dayStart(today), until: dayEnd(today) };
  if (operationPeriod.value === 'day')
    return {
      since: dayStart(operationDay.value || today),
      until: dayEnd(operationDay.value || today),
    };
  if (operationPeriod.value === 'month') {
    const month = operationMonth.value || monthInputValue();
    return {
      since: dayStart(`${month}-01`),
      until: dayEnd(monthEndDate(month)),
    };
  }
  const first = operationCustomStart.value || today;
  const last = operationCustomEnd.value || today;
  return {
    since: dayStart(first <= last ? first : last),
    until: dayEnd(first <= last ? last : first),
  };
});

const fetchOverview = async () => {
  isLoading.value = true;
  try {
    const { data } = await SinalReportsAPI.getOverview({
      ...epochRange.value,
      inboxId: inboxParam.value,
    });
    overview.value = data;
  } finally {
    isLoading.value = false;
  }
};

const fetchOperations = async () => {
  const { data } = await SinalReportsAPI.getOperations({
    ...operationRange.value,
    inboxId: inboxParam.value,
  });
  agents.value = data.agents || [];
};

onMounted(() => {
  fetchOverview();
  fetchOperations();
});
watch([days, selectedInboxId], () => {
  fetchOverview();
  fetchOperations();
});
watch(operationRange, fetchOperations);

const up = computed(() => (overview.value?.kpis?.pct_change ?? 0) >= 0);

const goToAiReports = () => {
  router.push({
    name: 'ai_reports',
    params: { accountId: route.params.accountId },
  });
};
</script>

<template>
  <SinalShell>
    <div v-if="isLoading" class="flex items-center justify-center h-[60vh]">
      <Spinner />
    </div>
    <div v-else class="flex flex-col gap-4">
      <!-- Seletor de período + caixa -->
      <div
        class="flex flex-wrap items-center justify-between gap-3 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-3.5 sm:p-4"
      >
        <div class="min-w-0">
          <div
            class="text-[10.5px] font-bold uppercase tracking-wider text-[var(--muted-2)] flex items-center gap-1.5"
          >
            <span class="i-lucide-building-2 size-3.5 text-[var(--accent)]" />
            {{ $t('SINAL_REPORTS.OVERVIEW.INBOX_LABEL') }}
          </div>
          <div class="text-sm font-bold text-[var(--text)] truncate mt-0.5">
            {{
              selectedInbox
                ? selectedInbox.name
                : $t('SINAL_REPORTS.OVERVIEW.ALL_INBOXES')
            }}
          </div>
        </div>
        <div class="flex items-center gap-2">
          <div
            class="flex items-center rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-0.5"
          >
            <button
              v-for="period in PERIODS"
              :key="period"
              class="px-2.5 py-1 rounded-md text-xs font-semibold transition-colors"
              :class="
                days === period
                  ? 'bg-[var(--surface)] text-[var(--accent)] shadow-sm'
                  : 'text-[var(--muted)]'
              "
              @click="days = period"
            >
              {{ `${period}d` }}
            </button>
          </div>
          <select
            v-model="selectedInboxId"
            class="h-9 min-w-[180px] max-w-[320px] rounded-lg bg-[var(--surface-2)] border border-[var(--border-soft)] px-3 text-xs font-semibold text-[var(--text)] outline-none focus:border-[var(--accent)] transition-colors"
          >
            <option value="all">
              {{ $t('SINAL_REPORTS.OVERVIEW.ALL_INBOXES') }}
            </option>
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </div>
      </div>

      <!-- KPIs -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-3.5">
        <HardCard
          icon="i-lucide-inbox"
          icon-class="text-emerald-600 dark:text-emerald-400"
          :label="`${$t('SINAL_REPORTS.OVERVIEW.KPI_RECEIVED')} (${days}d)`"
          :value="overview?.kpis?.received ?? 0"
          :hint="$t('SINAL_REPORTS.OVERVIEW.KPI_RECEIVED_HINT', { days })"
          :badge="`${up ? '+' : ''}${overview?.kpis?.pct_change ?? 0}%`"
          :badge-negative="!up"
        />
        <HardCard
          icon="i-lucide-send"
          icon-class="text-blue-600 dark:text-blue-400"
          :label="$t('SINAL_REPORTS.OVERVIEW.KPI_SENT')"
          :value="overview?.kpis?.sent ?? 0"
          :hint="$t('SINAL_REPORTS.OVERVIEW.KPI_SENT_HINT')"
        />
        <HardCard
          icon="i-lucide-mic"
          icon-class="text-amber-600 dark:text-amber-400"
          :label="$t('SINAL_REPORTS.OVERVIEW.KPI_AUDIOS')"
          :value="overview?.kpis?.audios ?? 0"
          :hint="$t('SINAL_REPORTS.OVERVIEW.KPI_AUDIOS_HINT')"
        />
      </div>

      <!-- Gráfico comparativo -->
      <div
        class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
      >
        <div class="flex items-center justify-between mb-4">
          <div>
            <h3
              class="text-sm font-bold text-[var(--text)] flex items-center gap-2"
            >
              <span class="i-lucide-activity size-4 text-[var(--accent)]" />
              {{ $t('SINAL_REPORTS.OVERVIEW.CHART_TITLE') }}
            </h3>
            <p class="text-xs text-[var(--muted)] mt-0.5">
              {{ $t('SINAL_REPORTS.OVERVIEW.CHART_SUBTITLE') }}
            </p>
          </div>
          <span
            class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-bold"
            :class="
              up
                ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                : 'bg-red-500/10 text-red-600 dark:text-red-400'
            "
          >
            <span
              :class="up ? 'i-lucide-trending-up' : 'i-lucide-trending-down'"
              class="size-3.5"
            />
            {{ `${overview?.kpis?.pct_change ?? 0}%` }}
          </span>
        </div>
        <AreaCompareChart :series="overview?.series ?? []" :height="220" />
      </div>

      <!-- Operação + IA -->
      <div class="grid grid-cols-1 lg:grid-cols-[1.2fr_1fr] gap-4">
        <div
          class="bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-5"
        >
          <div class="flex flex-wrap items-center justify-between gap-3 mb-3">
            <h3
              class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2"
            >
              <span class="i-lucide-user-round size-3.5 text-blue-500" />
              {{ $t('SINAL_REPORTS.OVERVIEW.OPERATIONS_TITLE') }}
            </h3>
            <div class="flex flex-wrap items-center gap-1.5">
              <select
                v-model="operationPeriod"
                class="h-8 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2.5 text-xs font-semibold text-[var(--text)] outline-none focus:border-[var(--accent)]"
              >
                <option value="today">
                  {{ $t('SINAL_REPORTS.OVERVIEW.PERIOD_TODAY') }}
                </option>
                <option value="day">
                  {{ $t('SINAL_REPORTS.OVERVIEW.PERIOD_DAY') }}
                </option>
                <option value="month">
                  {{ $t('SINAL_REPORTS.OVERVIEW.PERIOD_MONTH') }}
                </option>
                <option value="custom">
                  {{ $t('SINAL_REPORTS.OVERVIEW.PERIOD_CUSTOM') }}
                </option>
              </select>
              <input
                v-if="operationPeriod === 'day'"
                v-model="operationDay"
                type="date"
                class="h-8 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2 text-xs text-[var(--text)]"
              />
              <input
                v-if="operationPeriod === 'month'"
                v-model="operationMonth"
                type="month"
                class="h-8 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2 text-xs text-[var(--text)]"
              />
              <template v-if="operationPeriod === 'custom'">
                <input
                  v-model="operationCustomStart"
                  type="date"
                  class="h-8 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2 text-xs text-[var(--text)]"
                />
                <input
                  v-model="operationCustomEnd"
                  type="date"
                  class="h-8 rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] px-2 text-xs text-[var(--text)]"
                />
              </template>
            </div>
          </div>
          <div class="max-h-[380px] overflow-y-auto pr-1 overflow-x-auto">
            <div class="min-w-[480px]">
              <div
                v-for="agent in agents"
                :key="agent.agent_id"
                class="grid grid-cols-[minmax(0,1fr)_82px_92px_92px] gap-3 items-center py-2.5 border-b border-[var(--border-soft)] last:border-0"
              >
                <div class="min-w-0">
                  <div
                    class="text-[13px] font-semibold text-[var(--text)] truncate"
                  >
                    {{ agent.agent_name }}
                  </div>
                  <div
                    class="mt-0.5 flex min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5 text-[11px] text-[var(--muted)]"
                  >
                    <span>
                      {{ $t('SINAL_REPORTS.OVERVIEW.LAST_REPLY') }}
                      {{ timeAgo(agent.last_message_at) }}
                    </span>
                    <span
                      class="inline-flex items-center gap-1"
                      :class="
                        agent.online
                          ? 'text-emerald-600 dark:text-emerald-400 font-medium'
                          : 'text-[var(--muted-2)]'
                      "
                    >
                      <span
                        class="h-1.5 w-1.5 rounded-full"
                        :class="
                          agent.online
                            ? 'bg-emerald-500 ring-2 ring-emerald-500/20'
                            : 'bg-[var(--muted-2)]'
                        "
                      />
                      {{
                        agent.online
                          ? $t('SINAL_REPORTS.OVERVIEW.ONLINE')
                          : $t('SINAL_REPORTS.OVERVIEW.OFFLINE')
                      }}
                    </span>
                  </div>
                </div>
                <div class="text-right">
                  <div
                    class="font-display text-[16px] font-bold text-[var(--text)]"
                  >
                    {{ formatNumber(agent.messages_sent) }}
                  </div>
                  <div class="text-[10px] text-[var(--muted-2)]">
                    {{ $t('SINAL_REPORTS.OVERVIEW.COL_MSGS') }}
                  </div>
                </div>
                <div class="text-right">
                  <div
                    class="font-display text-[16px] font-bold text-[var(--accent)]"
                  >
                    {{ formatNumber(agent.conversations_handled) }}
                  </div>
                  <div class="text-[10px] text-[var(--muted-2)]">
                    {{ $t('SINAL_REPORTS.OVERVIEW.COL_CONVERSATIONS') }}
                  </div>
                </div>
                <div class="text-right">
                  <div
                    class="font-display text-[16px] font-bold text-[var(--text)]"
                  >
                    {{ formatMinutes(agent.avg_response_minutes) }}
                  </div>
                  <div class="text-[10px] text-[var(--muted-2)]">
                    {{ $t('SINAL_REPORTS.OVERVIEW.COL_AVG_TIME') }}
                  </div>
                </div>
              </div>
              <div
                v-if="!agents.length"
                class="py-8 text-center text-[var(--muted-2)] text-xs"
              >
                {{ $t('SINAL_REPORTS.OVERVIEW.NO_AGENTS') }}
              </div>
            </div>
          </div>
        </div>

        <div
          class="bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-5 flex flex-col justify-between"
        >
          <div>
            <div class="flex items-center justify-between mb-3">
              <h3
                class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2"
              >
                <span class="i-lucide-bot size-3.5 text-purple-500" />
                {{ $t('SINAL_REPORTS.OVERVIEW.IA_TITLE') }}
              </h3>
              <span class="text-[10.5px] text-[var(--muted-2)] font-mono">
                {{ `${days}d` }}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-2.5">
              <div
                class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
              >
                <div class="text-[11px] font-semibold text-[var(--muted)]">
                  {{ $t('SINAL_REPORTS.IA.AI_MESSAGES') }}
                </div>
                <div
                  class="text-xl font-bold text-purple-600 dark:text-purple-400 mt-1 font-display"
                >
                  {{ formatNumber(overview?.ia?.ai_messages ?? 0) }}
                </div>
              </div>
              <div
                class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
              >
                <div class="text-[11px] font-semibold text-[var(--muted)]">
                  {{ $t('SINAL_REPORTS.IA.PIX_RESERVATIONS') }}
                </div>
                <div
                  class="text-xl font-bold text-amber-600 dark:text-amber-400 mt-1 font-display"
                >
                  {{
                    formatNumber(
                      (overview?.ia?.reservations_created ?? 0) +
                        (overview?.ia?.pix_paid ?? 0)
                    )
                  }}
                </div>
              </div>
              <div
                class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
              >
                <div class="text-[11px] font-semibold text-[var(--muted)]">
                  {{ $t('SINAL_REPORTS.IA.HANDOFFS') }}
                </div>
                <div
                  class="text-xl font-bold text-blue-600 dark:text-blue-400 mt-1 font-display"
                >
                  {{ formatNumber(overview?.ia?.handoffs ?? 0) }}
                </div>
              </div>
              <div
                class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
              >
                <div class="text-[11px] font-semibold text-[var(--muted)]">
                  {{ $t('SINAL_REPORTS.IA.AUTO_CLOSURES') }}
                </div>
                <div
                  class="text-xl font-bold text-emerald-600 dark:text-emerald-400 mt-1 font-display"
                >
                  {{ formatNumber(overview?.ia?.auto_closures ?? 0) }}
                </div>
              </div>
            </div>
          </div>
          <div
            class="mt-4 pt-3 border-t border-[var(--border-soft)] flex items-center justify-between text-xs text-[var(--muted)]"
          >
            <span class="flex items-center gap-1.5">
              <span class="i-lucide-sparkles size-3.5 text-purple-500" />
              {{ $t('SINAL_REPORTS.OVERVIEW.IA_FOOTER') }}
            </span>
            <button
              type="button"
              class="text-[var(--accent)] font-semibold hover:underline"
              @click="goToAiReports"
            >
              {{ $t('SINAL_REPORTS.OVERVIEW.IA_AUDIT_LINK') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Nuvens -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
        >
          <div class="flex items-center justify-between mb-3">
            <h3
              class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2"
            >
              <span class="i-lucide-flame size-3.5 text-orange-500" />
              {{ $t('SINAL_REPORTS.OVERVIEW.TOPICS_TITLE') }}
            </h3>
            <span class="text-[11px] text-[var(--muted-2)]">
              {{ $t('SINAL_REPORTS.OVERVIEW.TOPICS_SOURCE') }}
            </span>
          </div>
          <WordCloud :items="overview?.topics ?? []" />
        </div>
        <div
          class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
        >
          <div class="flex items-center justify-between mb-3">
            <h3
              class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2"
            >
              <span class="i-lucide-tag size-3.5 text-cyan-500" />
              {{ $t('SINAL_REPORTS.OVERVIEW.LABELS_TITLE') }}
            </h3>
          </div>
          <WordCloud :items="overview?.labels ?? []" />
        </div>
      </div>
    </div>
  </SinalShell>
</template>
