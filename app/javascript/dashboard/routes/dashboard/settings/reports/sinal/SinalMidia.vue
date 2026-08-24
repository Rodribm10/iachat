<script setup>
// Réplica nativa da página Mídia do Sinal, alimentada pelos dados da conta.
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import SinalReportsAPI from 'dashboard/api/sinalReports';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SinalShell from './SinalShell.vue';
import SinalPeriodPicker from './SinalPeriodPicker.vue';
import StackedBars from './StackedBars.vue';
import {
  formatNumber,
  fmtDay,
  dateInputValue,
  computePeriodRange,
} from './helpers';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();

const MEDIA_TYPES = [
  { key: 'audio', icon: 'i-lucide-mic', color: '#F59E0B' },
  { key: 'image', icon: 'i-lucide-image', color: '#3B82F6' },
  { key: 'file', icon: 'i-lucide-file-text', color: '#8B5CF6' },
  { key: 'sticker', icon: 'i-lucide-sticker', color: '#EC4899' },
  { key: 'video', icon: 'i-lucide-video', color: '#10B981' },
];

const TYPE_LABEL_KEYS = {
  audio: 'SINAL_REPORTS.MIDIA.TYPE_AUDIO',
  image: 'SINAL_REPORTS.MIDIA.TYPE_IMAGE',
  file: 'SINAL_REPORTS.MIDIA.TYPE_FILE',
  sticker: 'SINAL_REPORTS.MIDIA.TYPE_STICKER',
  video: 'SINAL_REPORTS.MIDIA.TYPE_VIDEO',
};

const typeLabel = key => t(TYPE_LABEL_KEYS[key] || key);

const GRANULARITIES = [
  { key: 'day', labelKey: 'SINAL_REPORTS.MIDIA.GRANULARITY_DAY' },
  { key: 'week', labelKey: 'SINAL_REPORTS.MIDIA.GRANULARITY_WEEK' },
  { key: 'month', labelKey: 'SINAL_REPORTS.MIDIA.GRANULARITY_MONTH' },
];

const isLoading = ref(true);
const isLoadingChart = ref(false);
const isLoadingBreakdown = ref(false);
const isLoadingDrill = ref(false);
const isRefreshing = ref(false);

const periodPreset = ref('7');
const periodCustomStart = ref(dateInputValue());
const periodCustomEnd = ref(dateInputValue());

const summary = ref({ by_type: {}, stats: {}, range: {} });
const granularity = ref('day');
const timeseries = ref({ buckets: [] });
const breakdownScope = ref('individual');
const breakdown = ref({ rows: [] });

// drillFilter === null -> painel fechado. {} ou {type,direction} -> aberto.
const drillFilter = ref(null);
const drillMessages = ref([]);

// Recalculada a cada chamada (nunca cacheada) — presets relativos (7/14/30d)
// sempre usam o instante atual, mesmo com a página aberta há horas.
const currentRange = () =>
  computePeriodRange({
    preset: periodPreset.value,
    customStart: periodCustomStart.value,
    customEnd: periodCustomEnd.value,
  });

const fetchSummary = async () => {
  const { data } = await SinalReportsAPI.getMediaSummary(currentRange());
  summary.value = data;
};

const fetchTimeseries = async () => {
  isLoadingChart.value = true;
  try {
    const { data } = await SinalReportsAPI.getMediaTimeseries(
      granularity.value,
      currentRange()
    );
    timeseries.value = data;
  } finally {
    isLoadingChart.value = false;
  }
};

const fetchBreakdown = async () => {
  isLoadingBreakdown.value = true;
  try {
    const { data } = await SinalReportsAPI.getMediaBreakdown(
      breakdownScope.value,
      currentRange()
    );
    breakdown.value = data;
  } finally {
    isLoadingBreakdown.value = false;
  }
};

const fetchDrillMessages = async () => {
  isLoadingDrill.value = true;
  try {
    const { data } = await SinalReportsAPI.getMediaMessages({
      type: drillFilter.value?.type,
      direction: drillFilter.value?.direction,
      ...currentRange(),
    });
    drillMessages.value = data.messages || [];
  } finally {
    isLoadingDrill.value = false;
  }
};

// Dispara com o botão Atualizar e com qualquer troca no seletor de período.
// Reabastece tudo que depende do período; se o painel de drill estiver
// aberto, refaz ele também para não ficar com dado de outro período.
const refreshAll = async () => {
  isRefreshing.value = true;
  try {
    const tasks = [fetchSummary(), fetchTimeseries(), fetchBreakdown()];
    if (drillFilter.value) tasks.push(fetchDrillMessages());
    await Promise.all(tasks);
  } finally {
    isRefreshing.value = false;
  }
};

onMounted(async () => {
  isLoading.value = true;
  try {
    await Promise.all([fetchSummary(), fetchTimeseries(), fetchBreakdown()]);
  } finally {
    isLoading.value = false;
  }
});

watch([periodPreset, periodCustomStart, periodCustomEnd], refreshAll);
watch(granularity, fetchTimeseries);
watch(breakdownScope, fetchBreakdown);
watch(drillFilter, value => {
  if (value) fetchDrillMessages();
});

const totalByType = computed(() => summary.value.by_type || {});

const totalAll = computed(() =>
  MEDIA_TYPES.reduce((sum, t2) => sum + (totalByType.value[t2.key] || 0), 0)
);

const chartBuckets = computed(() =>
  (timeseries.value.buckets || []).map(bucket => ({
    label: granularity.value === 'day' ? fmtDay(bucket.bucket) : bucket.bucket,
    values: bucket.values || {},
  }))
);

const chartTypes = computed(() =>
  MEDIA_TYPES.map(type => ({
    key: type.key,
    label: typeLabel(type.key),
    color: type.color,
  }))
);

const spanDays = computed(() => {
  const { min_at: minAt, max_at: maxAt } = summary.value.range || {};
  if (!minAt || !maxAt) return 0;
  return Math.max(1, Math.ceil((new Date(maxAt) - new Date(minAt)) / 86400000));
});

const PER_DIVISORS = {
  day: days => days,
  week: days => days / 7,
  month: days => days / 30.44,
};

const avg = (total, per) => {
  if (!spanDays.value) return 0;
  const divisor = PER_DIVISORS[per](spanDays.value);
  return total / divisor;
};

const formatAvg = n =>
  n.toLocaleString('pt-BR', {
    maximumFractionDigits: 1,
    minimumFractionDigits: 1,
  });

const statFor = key => summary.value.stats?.[key] || {};

const totalStats = computed(() =>
  MEDIA_TYPES.reduce(
    (acc, type) => {
      const s = statFor(type.key);
      return {
        total: acc.total + (s.total || 0),
        incoming: acc.incoming + (s.incoming || 0),
        outgoing: acc.outgoing + (s.outgoing || 0),
        individual: acc.individual + (s.individual || 0),
        group: acc.group + (s.group || 0),
      };
    },
    { total: 0, incoming: 0, outgoing: 0, individual: 0, group: 0 }
  )
);

const audioStat = computed(() => statFor('audio'));

const openDrill = filter => {
  drillFilter.value = filter;
};

const closeDrill = () => {
  drillFilter.value = null;
};

const drillTitle = computed(() => {
  if (!drillFilter.value) return '';
  return drillFilter.value.type
    ? typeLabel(drillFilter.value.type)
    : t('SINAL_REPORTS.MIDIA.DRILL_TITLE_ALL');
});

const drillSubtitle = computed(() => {
  if (!drillFilter.value) return '';
  if (drillFilter.value.direction === 'incoming') {
    return t('SINAL_REPORTS.MIDIA.DRILL_RECEIVED');
  }
  if (drillFilter.value.direction === 'outgoing') {
    return t('SINAL_REPORTS.MIDIA.DRILL_SENT');
  }
  return drillFilter.value.type
    ? t('SINAL_REPORTS.MIDIA.DRILL_SUBTITLE_ALL_CHATS')
    : t('SINAL_REPORTS.MIDIA.DRILL_SUBTITLE_ALL_TYPES');
});

const iconForType = key =>
  MEDIA_TYPES.find(type => type.key === key)?.icon || 'i-lucide-file';

const openConversation = message => {
  router.push(
    `/app/accounts/${route.params.accountId}/conversations/${message.conversation_id}`
  );
};

const formatMessageDate = iso =>
  iso ? new Date(iso).toLocaleString('pt-BR') : '';
</script>

<template>
  <SinalShell>
    <div v-if="isLoading" class="flex items-center justify-center h-[60vh]">
      <Spinner />
    </div>
    <div v-else class="flex flex-col gap-4">
      <!-- Seletor de período -->
      <div
        class="flex flex-wrap items-center justify-end gap-3 bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-3.5 sm:p-4"
      >
        <SinalPeriodPicker
          v-model:preset="periodPreset"
          v-model:custom-start="periodCustomStart"
          v-model:custom-end="periodCustomEnd"
          :is-loading="isRefreshing"
          @refresh="refreshAll"
        />
      </div>

      <!-- Cards de inventário -->
      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <button
          type="button"
          class="text-left rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-4 flex flex-col gap-1 transition-colors hover:border-[var(--accent-border)] hover:bg-[var(--surface-2)]"
          @click="openDrill({})"
        >
          <div class="flex items-center gap-2 text-[var(--muted)]">
            <span class="i-lucide-layers size-4 text-[var(--accent)]" />
            <span class="text-[11px] uppercase tracking-wider font-semibold">
              {{ $t('SINAL_REPORTS.MIDIA.TOTAL') }}
            </span>
          </div>
          <div
            class="font-display text-2xl font-semibold text-[var(--text)] mt-1"
          >
            {{ formatNumber(totalAll) }}
          </div>
        </button>

        <button
          v-for="type in MEDIA_TYPES"
          :key="type.key"
          type="button"
          class="text-left rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-4 flex flex-col gap-1 transition-colors hover:border-[var(--accent-border)] hover:bg-[var(--surface-2)]"
          @click="openDrill({ type: type.key })"
        >
          <div class="flex items-center gap-2 text-[var(--muted)]">
            <span
              class="size-4"
              :class="[type.icon]"
              :style="{ color: type.color }"
            />
            <span class="text-[11px] uppercase tracking-wider font-semibold">
              {{ typeLabel(type.key) }}
            </span>
          </div>
          <div
            class="font-display text-2xl font-semibold text-[var(--text)] mt-1"
          >
            {{ formatNumber(totalByType[type.key] || 0) }}
          </div>
        </button>
      </div>

      <!-- Evolução por tipo -->
      <div
        class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
      >
        <div class="flex items-center justify-between mb-4 flex-wrap gap-3">
          <h3
            class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2"
          >
            <span class="i-lucide-bar-chart-3 size-3.5 text-[var(--accent)]" />
            {{ $t('SINAL_REPORTS.MIDIA.CHART_TITLE') }}
          </h3>
          <div
            class="inline-flex items-center rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-0.5 gap-0.5"
          >
            <button
              v-for="option in GRANULARITIES"
              :key="option.key"
              type="button"
              class="px-2.5 py-1 rounded-md text-xs font-semibold transition-colors"
              :class="
                granularity === option.key
                  ? 'bg-[var(--surface-3)] text-[var(--text)]'
                  : 'text-[var(--muted)]'
              "
              @click="granularity = option.key"
            >
              {{ $t(option.labelKey) }}
            </button>
          </div>
        </div>

        <div class="flex items-center flex-wrap gap-x-4 gap-y-1.5 mb-3.5">
          <div
            v-for="type in chartTypes"
            :key="type.key"
            class="flex items-center gap-1.5 text-xs text-[var(--muted)]"
          >
            <span
              class="w-2.5 h-2.5 rounded-sm"
              :style="{ backgroundColor: type.color }"
            />
            {{ type.label }}
          </div>
        </div>

        <div
          v-if="isLoadingChart"
          class="flex items-center justify-center h-[280px]"
        >
          <Spinner />
        </div>
        <StackedBars
          v-else-if="chartBuckets.length"
          :buckets="chartBuckets"
          :types="chartTypes"
          :height="280"
        />
        <div
          v-else
          class="flex items-center justify-center h-[280px] text-xs text-[var(--muted-2)]"
        >
          {{ $t('SINAL_REPORTS.MIDIA.CHART_EMPTY') }}
        </div>
      </div>

      <!-- Panorama por tipo -->
      <div
        class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
      >
        <div class="flex items-center justify-between mb-4 flex-wrap gap-2">
          <h3
            class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2"
          >
            <span class="i-lucide-table-2 size-3.5 text-[var(--accent)]" />
            {{ $t('SINAL_REPORTS.MIDIA.PANORAMA_TITLE') }}
          </h3>
          <span v-if="spanDays > 0" class="text-[11.5px] text-[var(--muted-2)]">
            {{ $t('SINAL_REPORTS.MIDIA.PANORAMA_HINT', { days: spanDays }) }}
          </span>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_TYPE') }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_TOTAL') }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_RECEIVED') }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_SENT') }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_INDIVIDUAL') }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_GROUPS') }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_PER_DAY') }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_PER_WEEK') }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_PER_MONTH') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="type in MEDIA_TYPES"
                :key="type.key"
                class="hover:bg-[var(--surface-2)] transition-colors"
              >
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13.5px] font-medium text-[var(--text)] cursor-pointer hover:text-[var(--accent)]"
                  @click="openDrill({ type: type.key })"
                >
                  <span class="inline-flex items-center gap-2">
                    <span
                      class="size-4"
                      :class="[type.icon]"
                      :style="{ color: type.color }"
                    />
                    {{ typeLabel(type.key) }}
                  </span>
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono font-semibold text-right text-[var(--text)] cursor-pointer hover:text-[var(--accent)]"
                  @click="openDrill({ type: type.key })"
                >
                  {{ formatNumber(statFor(type.key).total || 0) }}
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono text-right text-[var(--text)] cursor-pointer hover:text-[var(--accent)]"
                  @click="openDrill({ type: type.key, direction: 'incoming' })"
                >
                  {{ formatNumber(statFor(type.key).incoming || 0) }}
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono text-right text-[var(--text)] cursor-pointer hover:text-[var(--accent)]"
                  @click="openDrill({ type: type.key, direction: 'outgoing' })"
                >
                  {{ formatNumber(statFor(type.key).outgoing || 0) }}
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatNumber(statFor(type.key).individual || 0) }}
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatNumber(statFor(type.key).group || 0) }}
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatAvg(avg(statFor(type.key).total || 0, 'day')) }}
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatAvg(avg(statFor(type.key).total || 0, 'week')) }}
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatAvg(avg(statFor(type.key).total || 0, 'month')) }}
                </td>
              </tr>
              <tr class="bg-[var(--surface-2)] font-bold">
                <td
                  class="py-3 px-3 text-[13.5px] text-[var(--text)] cursor-pointer hover:text-[var(--accent)]"
                  @click="openDrill({})"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.ROW_TOTAL') }}
                </td>
                <td
                  class="py-3 px-3 text-[13px] font-mono text-right text-[var(--text)] cursor-pointer hover:text-[var(--accent)]"
                  @click="openDrill({})"
                >
                  {{ formatNumber(totalStats.total) }}
                </td>
                <td
                  class="py-3 px-3 text-[13px] font-mono text-right text-[var(--text)] cursor-pointer hover:text-[var(--accent)]"
                  @click="openDrill({ direction: 'incoming' })"
                >
                  {{ formatNumber(totalStats.incoming) }}
                </td>
                <td
                  class="py-3 px-3 text-[13px] font-mono text-right text-[var(--text)] cursor-pointer hover:text-[var(--accent)]"
                  @click="openDrill({ direction: 'outgoing' })"
                >
                  {{ formatNumber(totalStats.outgoing) }}
                </td>
                <td
                  class="py-3 px-3 text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatNumber(totalStats.individual) }}
                </td>
                <td
                  class="py-3 px-3 text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatNumber(totalStats.group) }}
                </td>
                <td
                  class="py-3 px-3 text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatAvg(avg(totalStats.total, 'day')) }}
                </td>
                <td
                  class="py-3 px-3 text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatAvg(avg(totalStats.total, 'week')) }}
                </td>
                <td
                  class="py-3 px-3 text-[13px] font-mono text-right text-[var(--muted)]"
                >
                  {{ formatAvg(avg(totalStats.total, 'month')) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="text-xs text-[var(--muted)] flex items-start gap-2 mt-3.5">
          <span
            class="i-lucide-mic size-4 shrink-0 mt-0.5"
            :style="{ color: MEDIA_TYPES[0].color }"
          />
          <span>
            {{
              $t('SINAL_REPORTS.MIDIA.AUDIO_NOTE', {
                total: formatNumber(audioStat.total || 0),
                incoming: formatNumber(audioStat.incoming || 0),
                outgoing: formatNumber(audioStat.outgoing || 0),
              })
            }}
          </span>
        </div>
      </div>

      <!-- Por contato / Por grupo -->
      <div
        class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
      >
        <div
          class="inline-flex items-center rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-0.5 gap-0.5 mb-4"
        >
          <button
            type="button"
            class="px-2.5 py-1 rounded-md text-xs font-semibold transition-colors"
            :class="
              breakdownScope === 'individual'
                ? 'bg-[var(--surface-3)] text-[var(--text)]'
                : 'text-[var(--muted)]'
            "
            @click="breakdownScope = 'individual'"
          >
            {{ $t('SINAL_REPORTS.MIDIA.TAB_CONTACTS') }}
          </button>
          <button
            type="button"
            class="px-2.5 py-1 rounded-md text-xs font-semibold transition-colors"
            :class="
              breakdownScope === 'group'
                ? 'bg-[var(--surface-3)] text-[var(--text)]'
                : 'text-[var(--muted)]'
            "
            @click="breakdownScope = 'group'"
          >
            {{ $t('SINAL_REPORTS.MIDIA.TAB_GROUPS') }}
          </button>
        </div>

        <div v-if="isLoadingBreakdown" class="flex justify-center py-10">
          <Spinner />
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3"
                >
                  {{
                    breakdownScope === 'individual'
                      ? $t('SINAL_REPORTS.MIDIA.BREAKDOWN_COL_CONTACT')
                      : $t('SINAL_REPORTS.MIDIA.BREAKDOWN_COL_GROUP')
                  }}
                </th>
                <th
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.COL_TOTAL') }}
                </th>
                <th
                  v-for="type in MEDIA_TYPES"
                  :key="type.key"
                  class="text-[11px] uppercase tracking-wider text-[var(--muted-2)] font-semibold pb-3 border-b border-[var(--border-soft)] px-3 text-right"
                >
                  <span class="inline-flex items-center gap-1.5 justify-end">
                    <span
                      class="size-3.5"
                      :class="[type.icon]"
                      :style="{ color: type.color }"
                    />
                    {{ typeLabel(type.key) }}
                  </span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(row, index) in breakdown.rows"
                :key="`${row.name}-${index}`"
                class="hover:bg-[var(--surface-2)] transition-colors"
              >
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13.5px] font-medium text-[var(--text)] max-w-[220px] truncate"
                >
                  {{ row.name }}
                </td>
                <td
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono font-semibold text-right text-[var(--text)]"
                >
                  {{ formatNumber(row.total) }}
                </td>
                <td
                  v-for="type in MEDIA_TYPES"
                  :key="type.key"
                  class="py-3 px-3 border-b border-[var(--border-soft)] text-[13px] font-mono text-right"
                  :class="
                    row.types?.[type.key]
                      ? 'text-[var(--text)]'
                      : 'text-[var(--muted-2)]'
                  "
                >
                  {{
                    row.types?.[type.key]
                      ? formatNumber(row.types[type.key])
                      : $t('SINAL_REPORTS.MIDIA.EMPTY_VALUE')
                  }}
                </td>
              </tr>
              <tr v-if="!breakdown.rows?.length">
                <td
                  :colspan="2 + MEDIA_TYPES.length"
                  class="py-8 text-center text-[13px] text-[var(--muted-2)]"
                >
                  {{ $t('SINAL_REPORTS.MIDIA.BREAKDOWN_EMPTY') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Painel de drill -->
    <div
      v-if="drillFilter"
      class="fixed inset-y-0 right-0 w-[460px] max-w-[92vw] bg-[var(--surface)] border-l border-[var(--border-soft)] z-50 overflow-y-auto flex flex-col"
    >
      <div
        class="flex items-start justify-between gap-3 p-5 border-b border-[var(--border-soft)]"
      >
        <div class="min-w-0">
          <h3
            class="font-display font-semibold text-base text-[var(--text)] truncate"
          >
            {{ drillTitle }}
          </h3>
          <p class="text-xs text-[var(--muted)] mt-1">
            {{ drillSubtitle }}
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 flex h-7 w-7 items-center justify-center rounded-lg text-[var(--muted)] hover:bg-[var(--surface-2)] hover:text-[var(--text)]"
          @click="closeDrill"
        >
          <span class="i-lucide-x size-4" />
        </button>
      </div>

      <div class="flex-1 p-5">
        <div v-if="isLoadingDrill" class="flex justify-center py-10">
          <Spinner />
        </div>
        <div
          v-else-if="!drillMessages.length"
          class="text-[13px] text-[var(--muted-2)] py-6 text-center"
        >
          {{ $t('SINAL_REPORTS.MIDIA.DRILL_EMPTY') }}
        </div>
        <div v-else class="space-y-3">
          <div
            v-for="message in drillMessages"
            :key="message.id"
            class="flex gap-2.5 py-3 border-b border-[var(--border-soft)] last:border-none cursor-pointer hover:bg-[var(--surface-2)] -mx-2 px-2 rounded-lg"
            @click="openConversation(message)"
          >
            <div
              class="w-[30px] h-[30px] rounded-lg flex items-center justify-center shrink-0"
              :class="
                message.direction === 'incoming'
                  ? 'bg-[var(--surface-3)] text-[var(--info)]'
                  : 'bg-[var(--accent-soft)] text-[var(--accent)]'
              "
            >
              <span class="size-4" :class="[iconForType(message.file_type)]" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-xs font-medium text-[var(--muted)] truncate">
                  {{ message.contact_name }}
                </span>
                <span
                  class="text-[10px] uppercase tracking-wider font-semibold shrink-0"
                  :class="
                    message.direction === 'incoming'
                      ? 'text-[var(--ok)]'
                      : 'text-[var(--accent)]'
                  "
                >
                  {{
                    message.direction === 'incoming'
                      ? $t('SINAL_REPORTS.MIDIA.DRILL_RECEIVED')
                      : $t('SINAL_REPORTS.MIDIA.DRILL_SENT')
                  }}
                </span>
              </div>
              <div class="text-[13.5px] leading-snug text-[var(--text)] mt-0.5">
                <span v-if="message.content">{{ message.content }}</span>
                <span v-else class="text-[var(--muted-2)] italic">
                  {{ $t('SINAL_REPORTS.MIDIA.DRILL_NO_CAPTION') }}
                </span>
              </div>
              <div class="font-mono text-[11px] text-[var(--muted-2)] mt-0.5">
                {{ formatMessageDate(message.created_at) }}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </SinalShell>
</template>
