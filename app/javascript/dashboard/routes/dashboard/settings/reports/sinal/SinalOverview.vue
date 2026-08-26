<script setup>
// Réplica nativa da página Overview do Sinal, alimentada pelos dados da conta.
import { ref, computed, onMounted, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import SinalReportsAPI from 'dashboard/api/sinalReports';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SinalShell from './SinalShell.vue';
import SinalPeriodPicker from './SinalPeriodPicker.vue';
import HardCard from './HardCard.vue';
import WordCloud from './WordCloud.vue';
import AreaCompareChart from './AreaCompareChart.vue';
import ServiceModeCard from './ServiceModeCard.vue';
import SystemAdoptionCard from './SystemAdoptionCard.vue';
import DonutCard from './DonutCard.vue';
import MonthlyChart from './MonthlyChart.vue';
import {
  timeAgo,
  formatMinutes,
  formatNumber,
  dateInputValue,
  monthInputValue,
  monthEndDate,
  computePeriodRange,
  SYSTEM_ADOPTION_COLORS,
} from './helpers';

const router = useRouter();
const route = useRoute();
const inboxes = useMapGetter('inboxes/getInboxes');

const periodPreset = ref('7');
const periodCustomStart = ref(dateInputValue());
const periodCustomEnd = ref(dateInputValue());
const selectedInboxId = ref('all');
const isLoading = ref(true);
const isRefreshing = ref(false);
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

// Nº de dias do período selecionado, só para os rótulos "(Xd)" da UI.
// Deriva de estado reativo explícito (preset/datas) — nunca de Date.now() —
// então não sofre do bug do range congelado.
const rangeDays = computed(() => {
  if (periodPreset.value === 'today') return 1;
  if (periodPreset.value === 'custom') {
    const { since, until } = computePeriodRange({
      preset: 'custom',
      customStart: periodCustomStart.value,
      customEnd: periodCustomEnd.value,
    });
    return Math.max(1, Math.round((until - since) / 86400));
  }
  return Number(periodPreset.value) || 7;
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

// Recalculada a cada chamada (nunca cacheada) — presets relativos (7/14/30d)
// sempre usam o instante atual, mesmo com a página aberta há horas.
const currentRange = () =>
  computePeriodRange({
    preset: periodPreset.value,
    customStart: periodCustomStart.value,
    customEnd: periodCustomEnd.value,
  });

const fetchOverview = async () => {
  isRefreshing.value = true;
  try {
    const { data } = await SinalReportsAPI.getOverview({
      ...currentRange(),
      inboxId: inboxParam.value,
    });
    overview.value = data;
  } finally {
    isRefreshing.value = false;
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
watch([periodPreset, periodCustomStart, periodCustomEnd], fetchOverview);
watch(selectedInboxId, () => {
  fetchOverview();
  fetchOperations();
});
watch(operationRange, fetchOperations);

const up = computed(() => (overview.value?.kpis?.pct_change ?? 0) >= 0);

// Fila do AGORA — o único bloco da página que ignora o filtro de período, de
// propósito: "tem alguém pendurado?" só faz sentido no presente.
const waiting = computed(() => overview.value?.waiting);
const hasWaiting = computed(() => (waiting.value?.total ?? 0) > 0);
const hasLate = computed(() => (waiting.value?.buckets?.late ?? 0) > 0);

const { t } = useI18n();
const visual = computed(() => overview.value?.visual);

const pct = (value, total) => {
  if (!total) return '0%';
  return `${Math.round((value / total) * 100)}%`;
};

const aiAttendedHint = (attended, total) =>
  t('SINAL_REPORTS.VISUAL.AI_ATTENDED_HINT', {
    attended: formatNumber(attended || 0),
    pct: pct(attended || 0, total || 0),
  });

const serviceModeSlices = computed(() => [
  {
    name: t('SINAL_REPORTS.SERVICE_MODE.AI_ONLY'),
    value: visual.value?.service_modes?.ai_only ?? 0,
    color: 'var(--accent)',
  },
  {
    name: t('SINAL_REPORTS.SERVICE_MODE.MIXED'),
    value: visual.value?.service_modes?.mixed ?? 0,
    color: '#A78BFA',
  },
  {
    name: t('SINAL_REPORTS.SERVICE_MODE.HUMAN_ONLY'),
    value: visual.value?.service_modes?.human_only ?? 0,
    color: '#FBBF24',
  },
]);

const systemAdoptionSplit = computed(() => [
  {
    name: t('SINAL_REPORTS.SYSTEM_ADOPTION.PANEL'),
    value: visual.value?.system_adoption?.panel ?? 0,
    color: SYSTEM_ADOPTION_COLORS.panel,
  },
  {
    name: t('SINAL_REPORTS.SYSTEM_ADOPTION.WHATSAPP_DIRECT'),
    value: visual.value?.system_adoption?.whatsapp_direct ?? 0,
    color: SYSTEM_ADOPTION_COLORS.whatsappDirect,
  },
]);

const participantSlices = computed(() => [
  {
    name: t('SINAL_REPORTS.VISUAL.PARTICIPANT_CLIENT'),
    value: visual.value?.participants?.client ?? 0,
    color: '#60A5FA',
  },
  {
    name: t('SINAL_REPORTS.VISUAL.PARTICIPANT_AI'),
    value: visual.value?.participants?.ai ?? 0,
    color: 'var(--accent)',
  },
  {
    name: t('SINAL_REPORTS.VISUAL.PARTICIPANT_HUMAN'),
    value: visual.value?.participants?.human ?? 0,
    color: '#FBBF24',
  },
  {
    name: t('SINAL_REPORTS.VISUAL.PARTICIPANT_OTHER'),
    value: visual.value?.participants?.other ?? 0,
    color: 'var(--muted-2)',
  },
]);

const inboundSlices = computed(() => [
  {
    name: t('SINAL_REPORTS.VISUAL.WINDOW_COMMERCIAL'),
    value: visual.value?.inbound_windows?.commercial ?? 0,
    color: '#4ADE80',
  },
  {
    name: t('SINAL_REPORTS.VISUAL.WINDOW_AFTER_HOURS'),
    value: visual.value?.inbound_windows?.after_hours ?? 0,
    color: '#A78BFA',
  },
  {
    name: t('SINAL_REPORTS.VISUAL.WINDOW_WEEKEND'),
    value: visual.value?.inbound_windows?.weekend ?? 0,
    color: '#FBBF24',
  },
]);

const formatSlices = computed(() => [
  {
    name: t('SINAL_REPORTS.VISUAL.FORMAT_TEXT'),
    value: visual.value?.formats?.text ?? 0,
    color: 'var(--accent)',
  },
  {
    name: t('SINAL_REPORTS.VISUAL.FORMAT_AUDIO'),
    value: visual.value?.formats?.audio ?? 0,
    color: '#FBBF24',
  },
  {
    name: t('SINAL_REPORTS.VISUAL.FORMAT_MEDIA'),
    value: visual.value?.formats?.media ?? 0,
    color: '#F472B6',
  },
]);

const sliceTotal = slices => slices.reduce((sum, item) => sum + item.value, 0);
const inboundOutsideCommercial = computed(
  () =>
    (visual.value?.inbound_windows?.after_hours ?? 0) +
    (visual.value?.inbound_windows?.weekend ?? 0)
);

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
          <SinalPeriodPicker
            v-model:preset="periodPreset"
            v-model:custom-start="periodCustomStart"
            v-model:custom-end="periodCustomEnd"
            :is-loading="isRefreshing"
            @refresh="fetchOverview"
          />
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

      <!-- Fila do momento: quem está esperando resposta agora -->
      <section
        class="bg-[var(--surface-2)] border rounded-xl p-[18px]"
        :class="hasLate ? 'border-amber-500/50' : 'border-[var(--border-soft)]'"
      >
        <div class="flex items-start justify-between gap-3 mb-3">
          <div>
            <h3 class="text-sm font-medium text-[var(--text-1)]">
              {{ $t('SINAL_REPORTS.OVERVIEW.WAITING_TITLE') }}
            </h3>
            <p class="text-xs text-[var(--text-3)] mt-0.5">
              {{ $t('SINAL_REPORTS.OVERVIEW.WAITING_SUBTITLE') }}
            </p>
          </div>
          <span
            v-if="hasWaiting"
            class="text-xs text-[var(--text-3)] whitespace-nowrap tabular-nums"
          >
            {{
              $t('SINAL_REPORTS.OVERVIEW.WAITING_OLDEST', {
                time: formatMinutes(waiting?.oldest_minutes ?? 0),
              })
            }}
          </span>
        </div>

        <div v-if="!hasWaiting" class="flex items-center gap-2">
          <span
            class="i-lucide-check-circle-2 size-4 text-emerald-600 dark:text-emerald-400"
          />
          <span class="text-sm text-[var(--text-2)]">
            {{ $t('SINAL_REPORTS.OVERVIEW.WAITING_EMPTY') }}
          </span>
          <span class="text-xs text-[var(--text-3)]">
            {{ $t('SINAL_REPORTS.OVERVIEW.WAITING_EMPTY_HINT') }}
          </span>
        </div>

        <div v-else class="flex flex-wrap items-end gap-x-8 gap-y-4">
          <div>
            <div class="flex items-baseline gap-2">
              <span
                class="text-3xl font-medium tabular-nums"
                :class="
                  hasLate
                    ? 'text-amber-600 dark:text-amber-400'
                    : 'text-[var(--text-1)]'
                "
              >
                {{ waiting?.total ?? 0 }}
              </span>
              <span class="text-xs text-[var(--text-3)]">
                {{
                  (waiting?.total ?? 0) === 1
                    ? $t('SINAL_REPORTS.OVERVIEW.WAITING_UNIT_ONE')
                    : $t('SINAL_REPORTS.OVERVIEW.WAITING_UNIT')
                }}
              </span>
            </div>
            <!-- Quem detém a conversa: sem isso não dá pra saber se o gargalo
                 é a IA ou a equipe. -->
            <div class="flex items-center gap-3 mt-1.5 text-xs">
              <span class="flex items-center gap-1.5 text-[var(--text-2)]">
                <span class="i-lucide-sparkles size-3 text-[var(--accent)]" />
                {{ waiting?.by_owner?.ai ?? 0 }}
                {{ $t('SINAL_REPORTS.OVERVIEW.WAITING_WITH_AI') }}
              </span>
              <span class="flex items-center gap-1.5 text-[var(--text-2)]">
                <span class="i-lucide-user-round size-3 text-[var(--text-3)]" />
                {{ waiting?.by_owner?.human ?? 0 }}
                {{ $t('SINAL_REPORTS.OVERVIEW.WAITING_WITH_HUMAN') }}
              </span>
            </div>
          </div>

          <div class="flex items-center gap-5">
            <div
              v-for="bucket in [
                {
                  key: 'recent',
                  label: $t('SINAL_REPORTS.OVERVIEW.WAITING_RECENT'),
                  dot: 'bg-[var(--text-3)]',
                },
                {
                  key: 'soon',
                  label: $t('SINAL_REPORTS.OVERVIEW.WAITING_SOON'),
                  dot: 'bg-amber-500',
                },
                {
                  key: 'late',
                  label: $t('SINAL_REPORTS.OVERVIEW.WAITING_LATE'),
                  dot: 'bg-red-500',
                },
              ]"
              :key="bucket.key"
              class="flex items-center gap-2"
            >
              <span :class="bucket.dot" class="rounded-full size-1.5" />
              <span class="text-sm tabular-nums text-[var(--text-1)]">
                {{ waiting?.buckets?.[bucket.key] ?? 0 }}
              </span>
              <span class="text-xs text-[var(--text-3)]">{{
                bucket.label
              }}</span>
            </div>
          </div>
        </div>
      </section>

      <!-- KPIs -->
      <div
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-5 gap-3.5"
      >
        <HardCard
          icon="i-lucide-user-plus"
          icon-class="text-emerald-600 dark:text-emerald-400"
          :label="`${$t('SINAL_REPORTS.VISUAL.KPI_NEW_LEADS')} (${rangeDays}d)`"
          :value="visual?.new_contacts ?? 0"
          :hint="
            aiAttendedHint(
              visual?.new_contacts_ai_attended,
              visual?.new_contacts
            )
          "
        />
        <HardCard
          icon="i-lucide-users-2"
          icon-class="text-[var(--accent)]"
          :label="`${$t('SINAL_REPORTS.VISUAL.KPI_CONTACTS')} (${rangeDays}d)`"
          :value="visual?.contacts ?? 0"
          :hint="aiAttendedHint(visual?.contacts_ai_attended, visual?.contacts)"
        />
        <HardCard
          icon="i-lucide-inbox"
          icon-class="text-emerald-600 dark:text-emerald-400"
          :label="`${$t('SINAL_REPORTS.OVERVIEW.KPI_RECEIVED')} (${rangeDays}d)`"
          :value="overview?.kpis?.received ?? 0"
          :hint="
            $t('SINAL_REPORTS.OVERVIEW.KPI_RECEIVED_HINT', {
              days: rangeDays,
            })
          "
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

      <!-- Panorama visual -->
      <section
        class="bg-[var(--surface-2)] border border-[var(--border-soft)] rounded-xl p-[18px]"
      >
        <div class="mb-4">
          <div class="flex items-center gap-2">
            <h2
              class="font-display text-[18px] font-semibold text-[var(--text)]"
            >
              {{ $t('SINAL_REPORTS.VISUAL.TITLE') }}
            </h2>
            <span
              class="rounded-full bg-[var(--accent-soft)] px-2 py-[3px] text-[10px] font-semibold text-[var(--accent)]"
            >
              {{ $t('SINAL_REPORTS.VISUAL.PERIOD_BADGE') }}
            </span>
          </div>
          <p class="mt-1 text-[12.5px] text-[var(--muted)]">
            {{ $t('SINAL_REPORTS.VISUAL.SUBTITLE') }}
          </p>
        </div>
        <ServiceModeCard
          :items="serviceModeSlices"
          :total-conversations="visual?.service_modes?.total ?? 0"
          :unclassified="visual?.service_modes?.unclassified ?? 0"
          :contacts="visual?.contacts ?? 0"
          :contacts-ai-attended="visual?.contacts_ai_attended ?? 0"
          :new-contacts="visual?.new_contacts ?? 0"
          :new-contacts-ai-attended="visual?.new_contacts_ai_attended ?? 0"
        />
        <div class="grid grid-cols-1 xl:grid-cols-3 gap-4">
          <DonutCard
            :title="$t('SINAL_REPORTS.VISUAL.PARTICIPANTS_TITLE')"
            :description="
              $t('SINAL_REPORTS.VISUAL.PARTICIPANTS_DESC', {
                total: formatNumber(sliceTotal(participantSlices)),
              })
            "
            :items="participantSlices"
            :unit="$t('SINAL_REPORTS.VISUAL.UNIT_MESSAGES')"
          >
            <template #footer>
              {{ $t('SINAL_REPORTS.VISUAL.PARTICIPANTS_FOOTER_PREFIX') }}
              <strong class="font-semibold text-[var(--accent)]">
                {{
                  pct(
                    visual?.participants?.ai ?? 0,
                    sliceTotal(participantSlices)
                  )
                }}
              </strong>
              {{ $t('SINAL_REPORTS.VISUAL.PARTICIPANTS_FOOTER_SUFFIX') }}
            </template>
          </DonutCard>
          <DonutCard
            :title="$t('SINAL_REPORTS.VISUAL.WINDOWS_TITLE')"
            :description="$t('SINAL_REPORTS.VISUAL.WINDOWS_DESC')"
            :items="inboundSlices"
            :unit="$t('SINAL_REPORTS.VISUAL.UNIT_MESSAGES')"
          >
            <template #footer>
              <strong class="font-semibold text-[#A78BFA]">
                {{ pct(inboundOutsideCommercial, sliceTotal(inboundSlices)) }}
              </strong>
              {{ $t('SINAL_REPORTS.VISUAL.WINDOWS_FOOTER') }}
            </template>
          </DonutCard>
          <DonutCard
            :title="$t('SINAL_REPORTS.VISUAL.FORMATS_TITLE')"
            :description="
              $t('SINAL_REPORTS.VISUAL.FORMATS_DESC', {
                total: formatNumber(sliceTotal(formatSlices)),
              })
            "
            :items="formatSlices"
            :unit="$t('SINAL_REPORTS.VISUAL.UNIT_MESSAGES')"
          >
            <template #footer>
              {{ $t('SINAL_REPORTS.VISUAL.FORMATS_FOOTER_PREFIX') }}
              <strong class="font-semibold text-[var(--warn)]">
                {{ pct(visual?.formats?.audio ?? 0, sliceTotal(formatSlices)) }}
              </strong>
              {{ $t('SINAL_REPORTS.VISUAL.FORMATS_FOOTER_SUFFIX') }}
            </template>
          </DonutCard>
        </div>
      </section>

      <!-- Adoção do sistema: painel x WhatsApp direto -->
      <SystemAdoptionCard
        :split-items="systemAdoptionSplit"
        :heatmap="visual?.system_adoption?.heatmap ?? []"
      />

      <!-- Visão mensal -->
      <section
        class="bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-[22px]"
      >
        <div class="flex flex-wrap items-start justify-between gap-3 mb-4">
          <div>
            <h2
              class="font-display text-[18px] font-semibold text-[var(--text)]"
            >
              {{ $t('SINAL_REPORTS.MONTHLY.TITLE') }}
            </h2>
            <p class="mt-1 text-[12.5px] text-[var(--muted)]">
              {{ $t('SINAL_REPORTS.MONTHLY.SUBTITLE') }}
            </p>
          </div>
          <div
            class="flex flex-wrap items-center gap-x-3 gap-y-1 text-[11px] text-[var(--muted)]"
          >
            <span class="inline-flex items-center gap-1.5">
              <span class="h-2 w-2 rounded-full bg-[var(--accent)]" />
              {{ $t('SINAL_REPORTS.MONTHLY.AI') }}
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span class="h-2 w-2 rounded-full bg-[#FBBF24]" />
              {{ $t('SINAL_REPORTS.MONTHLY.HUMAN') }}
            </span>
            <span class="inline-flex items-center gap-1.5">
              <span class="h-2 w-2 rounded-full bg-[var(--muted)]" />
              {{ $t('SINAL_REPORTS.MONTHLY.RECEIVED') }}
            </span>
          </div>
        </div>
        <MonthlyChart :months="visual?.months ?? []" :height="250" />
      </section>

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
                {{ `${rangeDays}d` }}
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
