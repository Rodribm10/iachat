<script setup>
import { ref, onMounted, onUnmounted, computed, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import SettingsLayout from '../../SettingsLayout.vue';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();

const inboxes = useMapGetter('inboxes/getInboxes');
const insights = useMapGetter('captainReports/getInsights');
const uiFlags = useMapGetter('captainReports/getUIFlags');

const activeTab = ref('insights');
const selectedInboxId = ref(null);
const selectedPeriod = ref('last_week');
const customStartDate = ref('');
const customEndDate = ref('');

const tabs = [{ key: 'insights' }, { key: 'operational' }];

const getPeriodDates = period => {
  const end = new Date();
  const start = new Date();

  switch (period) {
    case 'last_7_days':
      start.setDate(end.getDate() - 7);
      break;
    case 'last_week': {
      // Segunda a Domingo da semana passada
      const day = end.getDay();
      const diffToLastSunday = day === 0 ? 7 : day;
      end.setDate(end.getDate() - diffToLastSunday);
      start.setDate(end.getDate() - 6);
      break;
    }
    case 'current_month':
      start.setDate(1);
      break;
    case 'custom':
      return {
        period_start: customStartDate.value,
        period_end: customEndDate.value,
      };
    default:
      start.setDate(end.getDate() - 7);
  }

  return {
    period_start: start.toISOString().split('T')[0],
    period_end: end.toISOString().split('T')[0],
  };
};

let pollInterval = null;

const startPolling = () => {
  if (pollInterval) return;
  pollInterval = setInterval(async () => {
    await store.dispatch('captainReports/fetchInsights', {
      inbox_id: selectedInboxId.value,
    });
  }, 10000);
};

const stopPolling = () => {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
};

const hasProcessingInsights = computed(() => {
  return insights.value?.some(
    i => i.status === 'pending' || i.status === 'processing'
  );
});

watch(hasProcessingInsights, newVal => {
  if (newVal) startPolling();
  else stopPolling();
});

onMounted(async () => {
  await store.dispatch('inboxes/get');
  await store.dispatch('captainReports/fetchInsights', {});
  if (hasProcessingInsights.value) startPolling();
});

onUnmounted(() => {
  stopPolling();
});

const onFilterChange = async event => {
  const value = event.target.value;
  selectedInboxId.value = value ? Number(value) : null;
  await store.dispatch('captainReports/fetchInsights', {
    inbox_id: selectedInboxId.value,
  });
};

const onPeriodChange = event => {
  selectedPeriod.value = event.target.value;
};

const onGenerateInsight = async () => {
  if (uiFlags.value.isGenerating) return;
  const { period_start, period_end } = getPeriodDates(selectedPeriod.value);

  if (!period_start || !period_end) {
    useAlert(t('CAPTAIN_REPORTS.GENERATE.DATE_REQUIRED'));
    return;
  }

  try {
    await store.dispatch('captainReports/generateInsight', {
      inbox_id: selectedInboxId.value,
      period_start,
      period_end,
    });
    useAlert(t('CAPTAIN_REPORTS.GENERATE.SUCCESS'));
  } catch (error) {
    const errorMessage =
      error?.response?.data?.message || t('CAPTAIN_REPORTS.GENERATE.ERROR');
    useAlert(errorMessage);
  }
};
const statusLabel = status => {
  const map = {
    pending: t('CAPTAIN_REPORTS.STATUS.PENDING'),
    processing: t('CAPTAIN_REPORTS.STATUS.PROCESSING'),
    done: t('CAPTAIN_REPORTS.STATUS.DONE'),
    failed: t('CAPTAIN_REPORTS.STATUS.FAILED'),
  };
  return map[status] || status;
};

const statusClass = status => {
  const map = {
    pending: 'bg-n-amber-2 text-n-amber-11',
    processing: 'bg-n-blue-2 text-n-blue-11',
    done: 'bg-n-teal-2 text-n-teal-11',
    failed: 'bg-n-ruby-2 text-n-ruby-11',
  };
  return map[status] || 'bg-n-slate-3 text-n-slate-11';
};

const formatDate = dateStr => {
  if (!dateStr) return '-';
  // Use YYYY, MM, DD bits to avoid timezone shift from standard Date parsing
  const parts = dateStr.split('-');
  if (parts.length === 3) {
    const [year, month, day] = parts;
    return `${day}/${month}/${year}`;
  }
  return new Date(dateStr).toLocaleDateString('pt-BR');
};

const periodLabel = insight =>
  `${formatDate(insight.period_start)} – ${formatDate(insight.period_end)}`;
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetchingInsights"
    :loading-message="t('CAPTAIN_REPORTS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CAPTAIN_REPORTS.TITLE')"
        :description="t('CAPTAIN_REPORTS.DESC')"
      >
        <template #actions>
          <div class="flex items-center gap-3">
            <select
              class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :value="selectedPeriod"
              @change="onPeriodChange"
            >
              <option value="last_7_days">
                {{ t('CAPTAIN_REPORTS.FILTER_DATE.LAST_7_DAYS') }}
              </option>
              <option value="last_week">
                {{ t('CAPTAIN_REPORTS.FILTER_DATE.LAST_WEEK') }}
              </option>
              <option value="current_month">
                {{ t('CAPTAIN_REPORTS.FILTER_DATE.CURRENT_MONTH') }}
              </option>
              <option value="custom">
                {{ t('CAPTAIN_REPORTS.FILTER_DATE.CUSTOM') }}
              </option>
            </select>

            <div
              v-if="selectedPeriod === 'custom'"
              class="flex items-center gap-2"
            >
              <input
                v-model="customStartDate"
                type="date"
                class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('CAPTAIN_REPORTS.FILTER_DATE.START')"
              />
              <span class="text-n-slate-9 mx-1">
                {{ t('CAPTAIN_REPORTS.FILTER_DATE.SEPARATOR') }}
              </span>
              <input
                v-model="customEndDate"
                type="date"
                class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                :placeholder="t('CAPTAIN_REPORTS.FILTER_DATE.END')"
              />
            </div>

            <select
              class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              @change="onFilterChange"
            >
              <option value="">
                {{ t('CAPTAIN_REPORTS.ALL_INBOXES') }}
              </option>
              <option
                v-for="inbox in inboxes"
                :key="inbox.id"
                :value="inbox.id"
              >
                {{ inbox.name }}
              </option>
            </select>

            <Button
              :label="t('CAPTAIN_REPORTS.GENERATE.BUTTON')"
              icon="i-lucide-sparkles"
              color="blue"
              :is-loading="uiFlags.isGenerating"
              @click="onGenerateInsight"
            />
          </div>
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="flex flex-col px-6 pb-8">
        <!-- Tabs -->
        <div class="mb-6 flex gap-1 border-b border-n-weak">
          <button
            v-for="tab in tabs"
            :key="tab.key"
            class="px-4 py-2 text-sm font-medium transition-colors"
            :class="
              activeTab === tab.key
                ? 'border-b-2 border-n-brand text-n-brand'
                : 'text-n-slate-10 hover:text-n-slate-12'
            "
            @click="activeTab = tab.key"
          >
            {{
              tab.key === 'insights'
                ? t('CAPTAIN_REPORTS.TABS.INSIGHTS')
                : t('CAPTAIN_REPORTS.TABS.OPERATIONAL')
            }}
          </button>
        </div>

        <!-- Tab: Insights de IA -->
        <div v-if="activeTab === 'insights'">
          <div v-if="insights && insights.length > 0" class="space-y-3">
            <div
              v-for="insight in insights"
              :key="insight.id"
              class="rounded-xl border border-n-weak bg-n-alpha-1 p-4"
            >
              <div class="flex items-start justify-between">
                <div>
                  <p class="mb-1 text-sm font-semibold text-n-slate-12">
                    {{ periodLabel(insight) }}
                  </p>
                  <p class="mb-2 text-xs text-n-slate-10">
                    {{ insight.conversations_count }}
                    {{ t('CAPTAIN_REPORTS.INSIGHT.CONVERSATIONS') }}
                    {{ insight.messages_count }}
                    {{ t('CAPTAIN_REPORTS.INSIGHT.MESSAGES') }}
                  </p>
                </div>
                <span
                  class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
                  :class="statusClass(insight.status)"
                >
                  {{ statusLabel(insight.status) }}
                </span>
              </div>

              <!-- top_topics -->
              <div
                v-if="insight.payload && insight.payload.top_topics?.length"
                class="mt-3"
              >
                <p class="mb-2 text-xs font-semibold uppercase text-n-slate-9">
                  {{ t('CAPTAIN_REPORTS.INSIGHT.TOP_TOPICS') }}
                </p>
                <div class="flex flex-wrap gap-2">
                  <span
                    v-for="topic in insight.payload.top_topics.slice(0, 5)"
                    :key="topic.topic"
                    class="inline-flex items-center gap-1 rounded-full bg-n-blue-2 px-2 py-1 text-xs text-n-blue-11"
                  >
                    {{ topic.topic }}
                    {{ t('CAPTAIN_REPORTS.INSIGHT.COUNT_PREFIX') }}
                    {{ topic.count }}
                    {{ t('CAPTAIN_REPORTS.INSIGHT.COUNT_SUFFIX') }}
                  </span>
                </div>
              </div>

              <!-- ai_failures -->
              <div
                v-if="insight.payload && insight.payload.ai_failures?.length"
                class="mt-3"
              >
                <p class="mb-2 text-xs font-semibold uppercase text-n-slate-9">
                  {{ t('CAPTAIN_REPORTS.INSIGHT.AI_FAILURES') }}
                </p>
                <ul class="space-y-1">
                  <li
                    v-for="(failure, idx) in insight.payload.ai_failures.slice(
                      0,
                      3
                    )"
                    :key="idx"
                    class="text-xs text-n-slate-11"
                  >
                    {{ t('CAPTAIN_REPORTS.INSIGHT.BULLET') }}
                    {{ failure.description }}
                  </li>
                </ul>
              </div>

              <!-- period_summary -->
              <div
                v-if="insight.payload && insight.payload.period_summary"
                class="mt-3 rounded-lg bg-n-alpha-2 p-3"
              >
                <p class="mb-0 text-xs italic text-n-slate-11">
                  {{ insight.payload.period_summary }}
                </p>
              </div>
            </div>
          </div>

          <!-- Empty State -->
          <div
            v-else
            class="flex flex-col items-center justify-center gap-4 py-20 text-center"
          >
            <div
              class="flex size-16 items-center justify-center rounded-full bg-n-blue-2"
            >
              <span class="i-lucide-bar-chart-2 size-8 text-n-blue-9" />
            </div>
            <div class="flex flex-col gap-1">
              <p class="mb-0 text-base font-medium text-n-slate-12">
                {{ t('CAPTAIN_REPORTS.EMPTY.TITLE') }}
              </p>
              <p class="mb-0 max-w-sm text-sm text-n-slate-10">
                {{ t('CAPTAIN_REPORTS.EMPTY.MESSAGE') }}
              </p>
            </div>
            <Button
              :label="t('CAPTAIN_REPORTS.GENERATE.BUTTON')"
              icon="i-lucide-sparkles"
              color="blue"
              :is-loading="uiFlags.isGenerating"
              @click="onGenerateInsight"
            />
          </div>
        </div>

        <!-- Tab: Operacional -->
        <div v-else-if="activeTab === 'operational'">
          <div
            class="flex flex-col items-center justify-center gap-4 py-20 text-center"
          >
            <div
              class="flex size-16 items-center justify-center rounded-full bg-n-amber-2"
            >
              <span class="i-lucide-construction size-8 text-n-amber-9" />
            </div>
            <p class="mb-0 text-base font-medium text-n-slate-12">
              {{ t('CAPTAIN_REPORTS.OPERATIONAL.COMING_SOON') }}
            </p>
            <p class="mb-0 max-w-sm text-sm text-n-slate-10">
              {{ t('CAPTAIN_REPORTS.OPERATIONAL.COMING_SOON_DESC') }}
            </p>
          </div>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
