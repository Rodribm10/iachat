<script setup>
// Réplica nativa da página Privado do Sinal, alimentada pelos dados da conta.
import { ref, computed, onMounted, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRouter, useRoute } from 'vue-router';
import SinalReportsAPI from 'dashboard/api/sinalReports';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import SinalShell from './SinalShell.vue';
import SinalPeriodPicker from './SinalPeriodPicker.vue';
import Sparkline from './Sparkline.vue';
import WordCloud from './WordCloud.vue';
import {
  timeAgo,
  formatMinutes,
  formatNumber,
  dateInputValue,
  computePeriodRange,
  SINAL_PALETTE,
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
const privado = ref(null);

const inboxParam = computed(() =>
  selectedInboxId.value === 'all' ? undefined : selectedInboxId.value
);

// Recalculada a cada chamada (nunca cacheada) — presets relativos (7/14/30d)
// sempre usam o instante atual, mesmo com a página aberta há horas.
const currentRange = () =>
  computePeriodRange({
    preset: periodPreset.value,
    customStart: periodCustomStart.value,
    customEnd: periodCustomEnd.value,
  });

const fetchPrivado = async () => {
  isRefreshing.value = true;
  try {
    const { data } = await SinalReportsAPI.getPrivado({
      ...currentRange(),
      inboxId: inboxParam.value,
    });
    privado.value = data;
  } finally {
    isRefreshing.value = false;
    isLoading.value = false;
  }
};

onMounted(fetchPrivado);
watch(
  [periodPreset, periodCustomStart, periodCustomEnd, selectedInboxId],
  fetchPrivado
);

const pctUp = computed(() => (privado.value?.kpis?.pct_change ?? 0) >= 0);
const pctChangeLabel = computed(() => {
  const pct = privado.value?.kpis?.pct_change ?? 0;
  return `${pctUp.value ? '+' : ''}${pct}%`;
});
const unattendedCount = computed(
  () => privado.value?.kpis?.unattended_count ?? 0
);

const sortedInboxes = computed(() =>
  [...(privado.value?.inboxes ?? [])].sort(
    (a, b) => b.unanswered - a.unanswered || b.inbound - a.inbound
  )
);
const maxInboxInbound = computed(() =>
  Math.max(1, ...sortedInboxes.value.map(inbox => inbox.inbound))
);

const toggleInbox = inboxId => {
  const id = String(inboxId);
  selectedInboxId.value = selectedInboxId.value === id ? 'all' : id;
};

const inboxBarStyle = (inbox, index) => {
  const color = SINAL_PALETTE[index % SINAL_PALETTE.length];
  const pct = Math.max(
    4,
    Math.round((inbox.inbound / maxInboxInbound.value) * 100)
  );
  return {
    width: `${pct}%`,
    background: `linear-gradient(90deg, ${color}66, ${color})`,
  };
};

const topTopics = computed(() => (privado.value?.topics ?? []).slice(0, 10));
const maxTopicCount = computed(() =>
  Math.max(1, ...topTopics.value.map(item => item.count))
);

const sortedLabels = computed(() =>
  [...(privado.value?.labels ?? [])].sort((a, b) => b.count - a.count)
);
const maxLabelCount = computed(() =>
  Math.max(1, ...sortedLabels.value.map(label => label.count))
);
const labelColor = (label, index) =>
  label.color || SINAL_PALETTE[index % SINAL_PALETTE.length];

const initials = name => (name || '').substring(0, 2).toUpperCase() || 'U';

const isStale = iso => {
  if (!iso) return false;
  return Date.now() - new Date(iso).getTime() > 48 * 3600 * 1000;
};

const openConversation = row => {
  router.push(
    `/app/accounts/${route.params.accountId}/conversations/${row.conversation_id}`
  );
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
        <SinalPeriodPicker
          v-model:preset="periodPreset"
          v-model:custom-start="periodCustomStart"
          v-model:custom-end="periodCustomEnd"
          :is-loading="isRefreshing"
          @refresh="fetchPrivado"
        />
        <select
          v-model="selectedInboxId"
          class="h-9 min-w-[180px] max-w-[320px] rounded-lg bg-[var(--surface-2)] border border-[var(--border-soft)] px-3 text-xs font-semibold text-[var(--text)] outline-none focus:border-[var(--accent)] transition-colors"
        >
          <option value="all">
            {{ $t('SINAL_REPORTS.PRIVADO.ALL_INBOXES') }}
          </option>
          <option
            v-for="inbox in inboxes"
            :key="inbox.id"
            :value="String(inbox.id)"
          >
            {{ inbox.name }}
          </option>
        </select>
      </div>

      <!-- KPIs -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3.5">
        <div
          class="bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-4"
        >
          <div
            class="text-[11px] text-[var(--muted)] mb-2 flex items-center gap-1.5"
          >
            <span class="w-[7px] h-[7px] rounded-full bg-[var(--accent)]" />
            {{ $t('SINAL_REPORTS.PRIVADO.KPI_RECEIVED') }}
          </div>
          <div class="flex items-end justify-between gap-2.5">
            <div class="shrink-0">
              <div
                class="font-display font-semibold text-2xl leading-none text-[var(--text)]"
              >
                {{ formatNumber(privado?.kpis?.avg_per_day ?? 0) }}
                <small class="text-[13px] text-[var(--muted)] ml-1">
                  {{ $t('SINAL_REPORTS.PRIVADO.KPI_RECEIVED_PER_DAY') }}
                </small>
              </div>
              <div
                class="text-[11px] mt-1.5 inline-flex items-center gap-1 font-medium"
                :class="pctUp ? 'text-[var(--ok)]' : 'text-[var(--danger)]'"
              >
                <span
                  :class="
                    pctUp ? 'i-lucide-trending-up' : 'i-lucide-trending-down'
                  "
                  class="size-3"
                />
                {{ pctChangeLabel }}
              </div>
            </div>
            <div class="flex-1 min-w-0 max-w-[150px]">
              <Sparkline :points="privado?.kpis?.sparkline ?? []" />
            </div>
          </div>
        </div>

        <div
          class="bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-4"
        >
          <div
            class="text-[11px] text-[var(--muted)] mb-2 flex items-center gap-1.5"
          >
            <span class="i-lucide-timer size-3.5 text-[var(--info)]" />
            {{ $t('SINAL_REPORTS.PRIVADO.KPI_RESPONSE_TIME') }}
          </div>
          <div
            class="font-display font-semibold text-2xl leading-none text-[var(--text)]"
          >
            {{ formatMinutes(privado?.kpis?.response_avg_minutes ?? null) }}
          </div>
          <div class="text-[11px] text-[var(--muted-2)] mt-1.5">
            {{
              $t('SINAL_REPORTS.PRIVADO.KPI_RESPONSE_TIME_DETAIL', {
                median: formatMinutes(
                  privado?.kpis?.response_median_minutes ?? null
                ),
                samples: formatNumber(privado?.kpis?.response_samples ?? 0),
              })
            }}
          </div>
        </div>

        <div
          class="bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-4"
        >
          <div
            class="text-[11px] text-[var(--muted)] mb-2 flex items-center gap-1.5"
          >
            <span
              class="i-lucide-message-circle size-3.5 text-[var(--accent)]"
            />
            {{ $t('SINAL_REPORTS.PRIVADO.KPI_OPEN_CONVERSATIONS') }}
          </div>
          <div
            class="font-display font-semibold text-2xl leading-none text-[var(--text)]"
          >
            {{ formatNumber(privado?.kpis?.open_count ?? 0) }}
          </div>
        </div>

        <div
          class="bg-[var(--surface)] border border-[var(--border-soft)] rounded-xl p-4"
        >
          <div
            class="text-[11px] text-[var(--muted)] mb-2 flex items-center gap-1.5"
          >
            <span class="i-lucide-alert-circle size-3.5 text-[var(--danger)]" />
            {{ $t('SINAL_REPORTS.PRIVADO.KPI_UNANSWERED') }}
          </div>
          <div
            class="font-display font-semibold text-2xl leading-none"
            :class="
              unattendedCount > 0
                ? 'text-[var(--danger)]'
                : 'text-[var(--text)]'
            "
          >
            {{ formatNumber(unattendedCount) }}
          </div>
        </div>
      </div>

      <!-- Indicadores da IA -->
      <div
        class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
      >
        <h3
          class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2 mb-3.5"
        >
          <span class="i-lucide-bot size-3.5 text-purple-500" />
          {{ $t('SINAL_REPORTS.PRIVADO.IA_TITLE') }}
        </h3>
        <div class="grid grid-cols-2 lg:grid-cols-3 gap-2.5">
          <div
            class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
          >
            <div class="text-[11px] font-semibold text-[var(--muted)]">
              {{ $t('SINAL_REPORTS.PRIVADO.IA_AI_MESSAGES') }}
            </div>
            <div
              class="text-xl font-bold text-purple-600 dark:text-purple-400 mt-1 font-display"
            >
              {{ formatNumber(privado?.ia?.ai_messages ?? 0) }}
            </div>
          </div>
          <div
            class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
          >
            <div class="text-[11px] font-semibold text-[var(--muted)]">
              {{ $t('SINAL_REPORTS.PRIVADO.IA_RESERVATIONS') }}
            </div>
            <div
              class="text-xl font-bold text-amber-600 dark:text-amber-400 mt-1 font-display"
            >
              {{ formatNumber(privado?.ia?.reservations_created ?? 0) }}
            </div>
          </div>
          <div
            class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
          >
            <div class="text-[11px] font-semibold text-[var(--muted)]">
              {{ $t('SINAL_REPORTS.PRIVADO.IA_PIX_PAID') }}
            </div>
            <div
              class="text-xl font-bold text-green-600 dark:text-green-400 mt-1 font-display"
            >
              {{ formatNumber(privado?.ia?.pix_paid ?? 0) }}
            </div>
          </div>
          <div
            class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
          >
            <div class="text-[11px] font-semibold text-[var(--muted)]">
              {{ $t('SINAL_REPORTS.PRIVADO.IA_HANDOFFS') }}
            </div>
            <div
              class="text-xl font-bold text-blue-600 dark:text-blue-400 mt-1 font-display"
            >
              {{ formatNumber(privado?.ia?.handoffs ?? 0) }}
            </div>
          </div>
          <div
            class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
          >
            <div class="text-[11px] font-semibold text-[var(--muted)]">
              {{ $t('SINAL_REPORTS.PRIVADO.IA_AUTO_CLOSURES') }}
            </div>
            <div
              class="text-xl font-bold text-emerald-600 dark:text-emerald-400 mt-1 font-display"
            >
              {{ formatNumber(privado?.ia?.auto_closures ?? 0) }}
            </div>
          </div>
          <div
            class="rounded-lg border border-[var(--border-soft)] bg-[var(--surface-2)] p-3"
          >
            <div class="text-[11px] font-semibold text-[var(--muted)]">
              {{ $t('SINAL_REPORTS.PRIVADO.IA_HUMAN_REQUESTS') }}
            </div>
            <div
              class="text-xl font-bold text-red-600 dark:text-red-400 mt-1 font-display"
            >
              {{ formatNumber(privado?.ia?.human_requests ?? 0) }}
            </div>
          </div>
        </div>
      </div>

      <!-- Comparativo por caixa de entrada -->
      <div
        class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
      >
        <h3
          class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2 mb-3.5"
        >
          <span class="i-lucide-building-2 size-3.5 text-[var(--accent)]" />
          {{ $t('SINAL_REPORTS.PRIVADO.INBOXES_TITLE') }}
        </h3>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-2.5">
          <button
            v-for="(inbox, index) in sortedInboxes"
            :key="inbox.inbox_id"
            type="button"
            class="text-left border rounded-lg p-3 transition-colors"
            :class="
              selectedInboxId === String(inbox.inbox_id)
                ? 'border-[var(--accent)] bg-[var(--accent-soft)]'
                : 'border-[var(--border-soft)] bg-[var(--surface-2)] hover:border-[var(--accent)]'
            "
            @click="toggleInbox(inbox.inbox_id)"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <div
                  class="text-[13px] font-semibold text-[var(--text)] truncate"
                >
                  {{ inbox.name }}
                </div>
                <div class="mt-1 text-[11px] text-[var(--muted-2)]">
                  {{
                    $t('SINAL_REPORTS.PRIVADO.INBOXES_STATS', {
                      inbound: formatNumber(inbox.inbound),
                      conversations: formatNumber(inbox.conversations),
                    })
                  }}
                </div>
              </div>
              <div v-if="inbox.unanswered > 0" class="text-right shrink-0">
                <div
                  class="font-display text-xl leading-none text-[var(--danger)]"
                >
                  {{ formatNumber(inbox.unanswered) }}
                </div>
                <div class="text-[10px] text-[var(--muted-2)]">
                  {{ $t('SINAL_REPORTS.PRIVADO.INBOXES_UNANSWERED') }}
                </div>
              </div>
            </div>
            <div
              class="mt-2.5 h-[7px] bg-[var(--surface-3)] rounded-full overflow-hidden"
            >
              <span
                class="block h-full rounded-full"
                :style="inboxBarStyle(inbox, index)"
              />
            </div>
          </button>
          <div
            v-if="!sortedInboxes.length"
            class="md:col-span-2 py-6 text-center text-[var(--muted-2)] text-xs"
          >
            {{ $t('SINAL_REPORTS.PRIVADO.INBOXES_EMPTY') }}
          </div>
        </div>
      </div>

      <!-- Temas + etiquetas -->
      <div class="grid grid-cols-1 lg:grid-cols-[1.5fr_1fr] gap-4">
        <div
          class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
        >
          <h3
            class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2 mb-3.5"
          >
            <span class="i-lucide-flame size-3.5 text-orange-500" />
            {{ $t('SINAL_REPORTS.PRIVADO.TOPICS_TITLE') }}
          </h3>
          <WordCloud :items="privado?.topics ?? []" />
          <div
            v-if="topTopics.length"
            class="flex flex-col mt-4 pt-4 border-t border-[var(--border-soft)]"
          >
            <div
              v-for="(item, index) in topTopics"
              :key="item.topic"
              class="flex items-center gap-3 py-2.5 border-b border-[var(--border-soft)] last:border-none"
            >
              <span
                class="font-mono text-xs text-[var(--muted-2)] w-[18px] shrink-0"
              >
                {{ String(index + 1).padStart(2, '0') }}
              </span>
              <div class="flex-1 min-w-0">
                <div
                  class="text-[13px] font-medium text-[var(--text)] truncate"
                >
                  {{ item.topic }}
                </div>
                <div
                  class="mt-1.5 h-[7px] bg-[var(--surface-3)] rounded-full overflow-hidden"
                >
                  <span
                    class="block h-full rounded-full"
                    :style="{
                      width: `${Math.round((item.count / maxTopicCount) * 100)}%`,
                      background: `linear-gradient(90deg, var(--accent), transparent)`,
                    }"
                  />
                </div>
              </div>
              <span
                class="font-mono text-xs font-semibold text-[var(--text)] shrink-0"
              >
                {{ formatNumber(item.count) }}
              </span>
            </div>
          </div>
        </div>

        <div
          class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
        >
          <h3
            class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2 mb-3.5"
          >
            <span class="i-lucide-tag size-3.5 text-cyan-500" />
            {{ $t('SINAL_REPORTS.PRIVADO.LABELS_TITLE') }}
          </h3>
          <div class="flex flex-col gap-0.5">
            <div
              v-for="(label, index) in sortedLabels"
              :key="label.topic"
              class="flex items-center gap-3 py-2"
            >
              <span
                class="w-[110px] text-xs font-medium text-[var(--text)] truncate inline-flex items-center gap-1.5 shrink-0"
              >
                <span
                  class="w-2 h-2 rounded-full shrink-0"
                  :style="{ backgroundColor: labelColor(label, index) }"
                />
                {{ label.topic }}
              </span>
              <span
                class="flex-1 h-2 bg-[var(--surface-3)] rounded-full overflow-hidden"
              >
                <span
                  class="block h-full rounded-full"
                  :style="{
                    width: `${Math.round((label.count / maxLabelCount) * 100)}%`,
                    backgroundColor: labelColor(label, index),
                  }"
                />
              </span>
              <span
                class="font-mono text-xs text-[var(--muted)] w-8 text-right shrink-0"
              >
                {{ formatNumber(label.count) }}
              </span>
            </div>
            <div
              v-if="!sortedLabels.length"
              class="py-6 text-center text-[var(--muted-2)] text-xs"
            >
              {{ $t('SINAL_REPORTS.PRIVADO.LABELS_EMPTY') }}
            </div>
          </div>
        </div>
      </div>

      <!-- Clientes sem resposta -->
      <div
        class="rounded-xl border border-[var(--border-soft)] bg-[var(--surface)] p-5"
      >
        <div class="flex items-center justify-between mb-3.5">
          <h3
            class="text-xs font-bold text-[var(--muted)] uppercase tracking-wider flex items-center gap-2"
          >
            <span class="i-lucide-alert-circle size-3.5 text-[var(--danger)]" />
            {{ $t('SINAL_REPORTS.PRIVADO.UNANSWERED_TITLE') }}
          </h3>
          <span class="font-mono text-[var(--muted)] text-xs">
            {{ formatNumber((privado?.unanswered ?? []).length) }}
          </span>
        </div>
        <div class="flex flex-col">
          <div
            v-for="row in privado?.unanswered ?? []"
            :key="row.conversation_id"
            class="flex items-center gap-3 py-2.5 px-2 rounded-lg hover:bg-[var(--surface-2)] cursor-pointer transition-colors"
            @click="openConversation(row)"
          >
            <div
              class="w-[34px] h-[34px] rounded-full flex items-center justify-center text-[13px] font-semibold shrink-0 bg-[var(--accent-soft)] text-[var(--accent)]"
            >
              {{ initials(row.contact_name) }}
            </div>
            <div class="flex-1 min-w-0">
              <div
                class="text-[13px] font-semibold text-[var(--text)] truncate"
              >
                {{
                  row.contact_name ||
                  $t('SINAL_REPORTS.PRIVADO.UNKNOWN_CONTACT')
                }}
              </div>
              <div class="text-[11px] text-[var(--muted)] truncate mt-0.5">
                {{ row.last_text }}
              </div>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <span
                class="text-[11px] px-2 py-0.5 rounded-full font-medium whitespace-nowrap bg-[rgba(248,113,113,0.13)] text-[var(--danger)]"
              >
                {{ $t('SINAL_REPORTS.PRIVADO.UNANSWERED_BADGE') }}
              </span>
              <span
                class="font-mono text-[11px] whitespace-nowrap"
                :class="
                  isStale(row.waiting_since)
                    ? 'text-[var(--danger)]'
                    : 'text-[var(--muted-2)]'
                "
              >
                {{ timeAgo(row.waiting_since) }}
              </span>
            </div>
          </div>
          <div
            v-if="!(privado?.unanswered ?? []).length"
            class="py-6 text-center text-[var(--muted-2)] text-xs"
          >
            {{ $t('SINAL_REPORTS.PRIVADO.UNANSWERED_EMPTY') }}
          </div>
        </div>
      </div>
    </div>
  </SinalShell>
</template>
