<script setup>
import { ref, reactive, onMounted, onUnmounted, computed, watch } from 'vue';
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
const assistants = useMapGetter('captainAssistants/getRecords');

const activeTab = ref('dashboard');
const selectedInboxId = ref(null);
const selectedPeriod = ref('last_week');
const customStartDate = ref('');
const customEndDate = ref('');
const expandedInsights = ref({});

const tabs = [
  { key: 'dashboard' },
  { key: 'insights' },
  { key: 'operational' },
];

const getPeriodDates = period => {
  const end = new Date();
  const start = new Date();

  switch (period) {
    case 'last_7_days':
      start.setDate(end.getDate() - 7);
      break;
    case 'last_week': {
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

// Auto-expand first done insight when loaded
watch(
  insights,
  newInsights => {
    if (Object.keys(expandedInsights.value).length) return;
    const first = newInsights?.find(i => i.status === 'done' && i.payload);
    if (first) expandedInsights.value = { [first.id]: true };
  },
  { immediate: false }
);

onMounted(async () => {
  await store.dispatch('inboxes/get');
  await store.dispatch('captainAssistants/get');
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
  const parts = dateStr.split('-');
  if (parts.length === 3) {
    const [year, month, day] = parts;
    return `${day}/${month}/${year}`;
  }
  return new Date(dateStr).toLocaleDateString('pt-BR');
};

const periodLabel = insight =>
  `${formatDate(insight.period_start)} – ${formatDate(insight.period_end)}`;

const toggleInsight = id => {
  expandedInsights.value = {
    ...expandedInsights.value,
    [id]: !expandedInsights.value[id],
  };
};

const isExpanded = id => !!expandedInsights.value[id];

const sentimentOf = insight => {
  const s = insight.payload?.sentiment;
  if (!s) return null;
  const total =
    (s.positive_count || 0) + (s.negative_count || 0) + (s.neutral_count || 0);
  if (total === 0) return null;
  return {
    positivePercent: Math.round(((s.positive_count || 0) / total) * 100),
    negativePercent: Math.round(((s.negative_count || 0) / total) * 100),
    neutralPercent: Math.round(((s.neutral_count || 0) / total) * 100),
    positive_count: s.positive_count || 0,
    negative_count: s.negative_count || 0,
    neutral_count: s.neutral_count || 0,
    total,
    summary: s.summary || '',
  };
};

const hasExpandableContent = insight =>
  insight.status === 'done' && insight.payload;

const tabLabel = key => {
  const map = {
    dashboard: t('CAPTAIN_REPORTS.TABS.DASHBOARD'),
    insights: t('CAPTAIN_REPORTS.TABS.INSIGHTS'),
    operational: t('CAPTAIN_REPORTS.TABS.OPERATIONAL'),
  };
  return map[key] || key;
};

// ── FAQ Quick-Add ──
const quickAddFaq = reactive({
  open: false,
  question: '',
  answer: '',
  assistantId: null,
  saving: false,
});

const openQuickAddFaq = question => {
  quickAddFaq.question = question;
  quickAddFaq.answer = '';
  quickAddFaq.saving = false;
  if (assistants.value?.length === 1) {
    quickAddFaq.assistantId = assistants.value[0].id;
  } else {
    quickAddFaq.assistantId = null;
  }
  quickAddFaq.open = true;
};

const closeQuickAddFaq = () => {
  quickAddFaq.open = false;
};

const submitQuickAddFaq = async () => {
  if (!quickAddFaq.question || !quickAddFaq.answer || !quickAddFaq.assistantId)
    return;
  quickAddFaq.saving = true;
  try {
    await store.dispatch('captainResponses/create', {
      question: quickAddFaq.question,
      answer: quickAddFaq.answer,
      assistant_id: quickAddFaq.assistantId,
    });
    useAlert(t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.SUCCESS'));
    closeQuickAddFaq();
  } catch {
    useAlert(t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.ERROR'));
  } finally {
    quickAddFaq.saving = false;
  }
};

// ── Dashboard aggregations ──
const doneInsights = computed(() =>
  (insights.value || []).filter(i => i.status === 'done' && i.payload)
);

const doneInsightsCount = computed(() => doneInsights.value.length);

const totalConversations = computed(() =>
  doneInsights.value.reduce((acc, i) => acc + (i.conversations_count || 0), 0)
);

const sentimentTrend = computed(() =>
  doneInsights.value
    .filter(i => i.payload?.sentiment)
    .map(i => {
      const s = i.payload.sentiment;
      const total =
        (s.positive_count || 0) +
        (s.negative_count || 0) +
        (s.neutral_count || 0);
      return {
        label: periodLabel(i),
        period_start: i.period_start,
        positivePercent:
          total > 0 ? Math.round(((s.positive_count || 0) / total) * 100) : 0,
        negativePercent:
          total > 0 ? Math.round(((s.negative_count || 0) / total) * 100) : 0,
        neutralPercent:
          total > 0 ? Math.round(((s.neutral_count || 0) / total) * 100) : 0,
      };
    })
    .sort((a, b) => (a.period_start || '').localeCompare(b.period_start || ''))
    .slice(-8)
);

const avgPositivePercent = computed(() => {
  if (!sentimentTrend.value.length) return null;
  const sum = sentimentTrend.value.reduce(
    (acc, w) => acc + w.positivePercent,
    0
  );
  return Math.round(sum / sentimentTrend.value.length);
});

const aggregatedFaqGaps = computed(() => {
  const map = {};
  doneInsights.value
    .filter(i => i.payload?.faq_gaps?.length)
    .forEach(i => {
      i.payload.faq_gaps.forEach(gap => {
        const key = (gap.question || '').toLowerCase().trim().slice(0, 80);
        if (!key) return;
        if (!map[key])
          map[key] = { question: gap.question, count: 0, weeks: 0 };
        map[key].count += gap.frequency || 1;
        map[key].weeks += 1;
      });
    });
  return Object.values(map)
    .sort((a, b) => b.count - a.count || b.weeks - a.weeks)
    .slice(0, 10);
});

const aggregatedTopics = computed(() => {
  const map = {};
  doneInsights.value
    .filter(i => i.payload?.top_topics?.length)
    .forEach(i => {
      i.payload.top_topics.forEach(topic => {
        const key = (topic.topic || '').toLowerCase().trim();
        if (!key) return;
        if (!map[key]) map[key] = { topic: topic.topic, count: 0 };
        map[key].count += topic.count || 1;
      });
    });
  return Object.values(map)
    .sort((a, b) => b.count - a.count)
    .slice(0, 8);
});

const maxTopicCount = computed(() =>
  Math.max(...aggregatedTopics.value.map(topic => topic.count), 1)
);

const aggregatedSuites = computed(() => {
  const map = {};
  doneInsights.value
    .filter(i => i.payload?.most_requested_suites?.length)
    .forEach(i => {
      i.payload.most_requested_suites.forEach(suite => {
        const key = (suite.suite || '').toLowerCase().trim();
        if (!key) return;
        if (!map[key]) map[key] = { suite: suite.suite, count: 0 };
        map[key].count += suite.count || 1;
      });
    });
  return Object.values(map)
    .sort((a, b) => b.count - a.count)
    .slice(0, 6);
});

const aggregatedFailures = computed(() => {
  const map = {};
  const sorted = [...doneInsights.value].sort((a, b) =>
    (a.period_start || '').localeCompare(b.period_start || '')
  );
  const half = Math.floor(sorted.length / 2);
  sorted.forEach((insight, idx) => {
    (insight.payload?.ai_failures || []).forEach(failure => {
      const key = (failure.description || '').toLowerCase().slice(0, 60);
      if (!key) return;
      if (!map[key])
        map[key] = {
          description: failure.description,
          total: 0,
          firstHalf: 0,
          secondHalf: 0,
        };
      map[key].total += failure.frequency || 1;
      if (idx < half) map[key].firstHalf += failure.frequency || 1;
      else map[key].secondHalf += failure.frequency || 1;
    });
  });
  return Object.values(map)
    .sort((a, b) => b.total - a.total)
    .slice(0, 8)
    .map(f => {
      let trend = 'stable';
      if (f.secondHalf > f.firstHalf) trend = 'up';
      else if (f.secondHalf < f.firstHalf) trend = 'down';
      return { ...f, trend };
    });
});

const complaintsTrend = computed(() =>
  doneInsights.value
    .filter(i => i.payload?.highlights?.complaints?.length)
    .map(i => ({
      label: periodLabel(i),
      period_start: i.period_start,
      count: i.payload.highlights.complaints.length,
    }))
    .sort((a, b) => (a.period_start || '').localeCompare(b.period_start || ''))
    .slice(-8)
);

const maxComplaintCount = computed(() =>
  Math.max(...complaintsTrend.value.map(w => w.count), 1)
);

const handoffProxy = computed(() =>
  doneInsights.value
    .filter(i => i.payload?.ai_failures?.length)
    .map(i => ({
      label: periodLabel(i),
      period_start: i.period_start,
      count: (i.payload.ai_failures || []).reduce(
        (sum, f) => sum + (f.frequency || 1),
        0
      ),
    }))
    .sort((a, b) => (a.period_start || '').localeCompare(b.period_start || ''))
    .slice(-8)
);

const maxHandoffCount = computed(() =>
  Math.max(...handoffProxy.value.map(w => w.count), 1)
);
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
          <div class="flex items-center gap-3 flex-wrap">
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
              />
              <span class="text-n-slate-9 mx-1">
                {{ t('CAPTAIN_REPORTS.FILTER_DATE.SEPARATOR') }}
              </span>
              <input
                v-model="customEndDate"
                type="date"
                class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
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
            {{ tabLabel(tab.key) }}
          </button>
        </div>

        <!-- Tab: Dashboard -->
        <div v-if="activeTab === 'dashboard'">
          <!-- No data state -->
          <div
            v-if="doneInsightsCount === 0"
            class="flex flex-col items-center justify-center gap-4 py-20 text-center"
          >
            <div
              class="flex size-16 items-center justify-center rounded-full bg-n-slate-2"
            >
              <span class="i-lucide-layout-dashboard size-8 text-n-slate-9" />
            </div>
            <p class="mb-0 max-w-sm text-sm text-n-slate-10">
              {{ t('CAPTAIN_REPORTS.DASHBOARD.NO_DATA') }}
            </p>
          </div>

          <div v-else class="space-y-6">
            <!-- KPI Cards -->
            <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
              <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
                <p class="text-2xl font-bold text-n-slate-12">
                  {{ totalConversations.toLocaleString() }}
                </p>
                <p class="mt-1 text-xs text-n-slate-9">
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.TOTAL_CONVERSATIONS') }}
                </p>
              </div>
              <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
                <p class="text-2xl font-bold text-n-teal-11">
                  {{
                    avgPositivePercent !== null ? avgPositivePercent + '%' : '—'
                  }}
                </p>
                <p class="mt-1 text-xs text-n-slate-9">
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.AVG_SENTIMENT') }}
                </p>
              </div>
              <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
                <p class="text-2xl font-bold text-n-amber-11">
                  {{ aggregatedFaqGaps.length }}
                </p>
                <p class="mt-1 text-xs text-n-slate-9">
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.FAQ_GAPS_TOTAL') }}
                </p>
              </div>
              <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
                <p class="text-2xl font-bold text-n-slate-12">
                  {{ doneInsightsCount }}
                </p>
                <p class="mt-1 text-xs text-n-slate-9">
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.WEEKS_ANALYZED') }}
                </p>
              </div>
            </div>

            <!-- Sentiment trend + AI Failures -->
            <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
              <!-- Sentiment trend -->
              <div
                v-if="sentimentTrend.length"
                class="rounded-2xl border border-n-weak bg-n-alpha-1 p-5"
              >
                <p
                  class="mb-4 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                >
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.SENTIMENT_TREND') }}
                </p>
                <div class="space-y-2">
                  <div
                    v-for="week in sentimentTrend"
                    :key="week.period_start"
                    class="flex items-center gap-3"
                  >
                    <span
                      class="w-28 shrink-0 text-xs text-n-slate-9 truncate"
                      >{{ week.label }}</span
                    >
                    <div
                      class="flex h-4 flex-1 overflow-hidden rounded-full bg-n-slate-3"
                    >
                      <div
                        class="bg-n-teal-9 transition-all"
                        :style="{ width: week.positivePercent + '%' }"
                      />
                      <div
                        class="bg-n-ruby-9 transition-all"
                        :style="{ width: week.negativePercent + '%' }"
                      />
                      <div
                        class="bg-n-slate-5 transition-all"
                        :style="{ width: week.neutralPercent + '%' }"
                      />
                    </div>
                    <span
                      class="w-10 shrink-0 text-right text-xs font-semibold text-n-teal-11"
                      >{{ week.positivePercent }}%</span
                    >
                  </div>
                </div>
                <div class="mt-3 flex gap-4">
                  <span
                    class="flex items-center gap-1.5 text-xs text-n-teal-11"
                  >
                    <span class="size-2 rounded-full bg-n-teal-9" />
                    {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_POSITIVE') }}
                  </span>
                  <span
                    class="flex items-center gap-1.5 text-xs text-n-ruby-11"
                  >
                    <span class="size-2 rounded-full bg-n-ruby-9" />
                    {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_NEGATIVE') }}
                  </span>
                  <span
                    class="flex items-center gap-1.5 text-xs text-n-slate-9"
                  >
                    <span class="size-2 rounded-full bg-n-slate-5" />
                    {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_NEUTRAL') }}
                  </span>
                </div>
              </div>

              <!-- AI Failures ranking -->
              <div
                v-if="aggregatedFailures.length"
                class="rounded-2xl border border-n-weak bg-n-alpha-1 p-5"
              >
                <p
                  class="mb-1 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                >
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.FAILURES_RANKING') }}
                </p>
                <p class="mb-4 text-xs text-n-slate-8">
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.FAILURES_RANKING_HINT') }}
                </p>
                <div class="space-y-2.5">
                  <div
                    v-for="(failure, idx) in aggregatedFailures"
                    :key="idx"
                    class="flex items-start gap-2"
                  >
                    <span
                      class="w-5 shrink-0 text-xs font-bold text-n-slate-7"
                      >{{ idx + 1 }}</span
                    >
                    <span
                      class="flex-1 text-xs text-n-slate-11 leading-relaxed"
                      >{{ failure.description }}</span
                    >
                    <div class="flex shrink-0 flex-col items-end gap-0.5">
                      <span class="text-xs font-semibold text-n-ruby-11"
                        >{{ failure.total
                        }}{{ t('CAPTAIN_REPORTS.INSIGHT.TIMES') }}</span
                      >
                      <span
                        class="text-xs"
                        :class="
                          failure.trend === 'up'
                            ? 'text-n-ruby-9'
                            : failure.trend === 'down'
                              ? 'text-n-teal-9'
                              : 'text-n-slate-8'
                        "
                      >
                        <span
                          :class="
                            failure.trend === 'up'
                              ? 'i-lucide-trending-up'
                              : failure.trend === 'down'
                                ? 'i-lucide-trending-down'
                                : 'i-lucide-minus'
                          "
                          class="size-3"
                        />
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- FAQ Priority -->
            <div
              v-if="aggregatedFaqGaps.length"
              class="rounded-2xl border border-n-amber-4 bg-n-amber-2 p-5"
            >
              <p
                class="mb-1 text-xs font-semibold uppercase tracking-wide text-n-amber-11"
              >
                {{ t('CAPTAIN_REPORTS.DASHBOARD.FAQ_PRIORITY') }}
              </p>
              <p class="mb-4 text-xs text-n-amber-9">
                {{ t('CAPTAIN_REPORTS.DASHBOARD.FAQ_PRIORITY_HINT') }}
              </p>
              <div class="space-y-2">
                <div
                  v-for="(gap, idx) in aggregatedFaqGaps"
                  :key="idx"
                  class="flex items-center gap-3 rounded-xl bg-n-alpha-1 px-3 py-2"
                >
                  <span class="w-5 shrink-0 text-xs font-bold text-n-amber-9">{{
                    idx + 1
                  }}</span>
                  <span class="flex-1 text-xs text-n-slate-11">{{
                    gap.question
                  }}</span>
                  <span class="shrink-0 text-xs text-n-slate-8"
                    >{{ gap.count
                    }}{{ t('CAPTAIN_REPORTS.INSIGHT.TIMES') }}</span
                  >
                  <button
                    class="shrink-0 rounded-full bg-n-amber-9 px-3 py-1 text-xs font-semibold text-white transition-opacity hover:opacity-80"
                    @click="openQuickAddFaq(gap.question)"
                  >
                    {{ t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.BUTTON') }}
                  </button>
                </div>
              </div>
            </div>

            <!-- Customer behavior -->
            <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
              <!-- Top topics -->
              <div
                v-if="aggregatedTopics.length"
                class="rounded-2xl border border-n-weak bg-n-alpha-1 p-5"
              >
                <p
                  class="mb-4 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                >
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.TOP_TOPICS_TITLE') }}
                </p>
                <div class="space-y-2">
                  <div
                    v-for="topic in aggregatedTopics"
                    :key="topic.topic"
                    class="flex items-center gap-2"
                  >
                    <span
                      class="w-28 shrink-0 truncate text-xs text-n-slate-11"
                      >{{ topic.topic }}</span
                    >
                    <div class="flex-1 rounded-full bg-n-slate-3 h-2">
                      <div
                        class="h-2 rounded-full bg-n-blue-8 transition-all"
                        :style="{
                          width:
                            Math.round((topic.count / maxTopicCount) * 100) +
                            '%',
                        }"
                      />
                    </div>
                    <span
                      class="w-8 shrink-0 text-right text-xs text-n-slate-9"
                      >{{ topic.count }}</span
                    >
                  </div>
                </div>
              </div>

              <!-- Most requested suites -->
              <div
                v-if="aggregatedSuites.length"
                class="rounded-2xl border border-n-weak bg-n-alpha-1 p-5"
              >
                <p
                  class="mb-4 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                >
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.SUITES_TITLE') }}
                </p>
                <div class="space-y-2">
                  <div
                    v-for="(suite, idx) in aggregatedSuites"
                    :key="suite.suite"
                    class="flex items-center gap-2"
                  >
                    <span
                      class="w-5 shrink-0 text-xs font-bold text-n-slate-7"
                      >{{ idx + 1 }}</span
                    >
                    <span class="flex-1 text-xs text-n-slate-11">{{
                      suite.suite
                    }}</span>
                    <span
                      class="shrink-0 rounded-full bg-n-slate-3 px-2 py-0.5 text-xs font-medium text-n-slate-9"
                    >
                      {{ suite.count }}{{ t('CAPTAIN_REPORTS.INSIGHT.TIMES') }}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Complaints trend + Handoffs -->
            <div class="grid grid-cols-1 gap-3 md:grid-cols-2">
              <!-- Complaints trend -->
              <div
                v-if="complaintsTrend.length"
                class="rounded-2xl border border-n-weak bg-n-alpha-1 p-5"
              >
                <p
                  class="mb-4 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                >
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.COMPLAINTS_TREND') }}
                </p>
                <div class="space-y-2">
                  <div
                    v-for="week in complaintsTrend"
                    :key="week.period_start"
                    class="flex items-center gap-3"
                  >
                    <span
                      class="w-28 shrink-0 text-xs text-n-slate-9 truncate"
                      >{{ week.label }}</span
                    >
                    <div class="flex-1 rounded-full bg-n-slate-3 h-3">
                      <div
                        class="h-3 rounded-full bg-n-ruby-7 transition-all"
                        :style="{
                          width:
                            Math.round((week.count / maxComplaintCount) * 100) +
                            '%',
                        }"
                      />
                    </div>
                    <span
                      class="w-6 shrink-0 text-right text-xs font-semibold text-n-ruby-11"
                      >{{ week.count }}</span
                    >
                  </div>
                </div>
              </div>

              <!-- Handoffs proxy -->
              <div
                v-if="handoffProxy.length"
                class="rounded-2xl border border-n-weak bg-n-alpha-1 p-5"
              >
                <p
                  class="mb-1 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                >
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.HANDOFFS_TITLE') }}
                </p>
                <p class="mb-4 text-xs text-n-slate-8 italic">
                  {{ t('CAPTAIN_REPORTS.DASHBOARD.HANDOFFS_HINT') }}
                </p>
                <div class="space-y-2">
                  <div
                    v-for="week in handoffProxy"
                    :key="week.period_start"
                    class="flex items-center gap-3"
                  >
                    <span
                      class="w-28 shrink-0 text-xs text-n-slate-9 truncate"
                      >{{ week.label }}</span
                    >
                    <div class="flex-1 rounded-full bg-n-slate-3 h-3">
                      <div
                        class="h-3 rounded-full bg-n-amber-7 transition-all"
                        :style="{
                          width:
                            Math.round((week.count / maxHandoffCount) * 100) +
                            '%',
                        }"
                      />
                    </div>
                    <span
                      class="w-6 shrink-0 text-right text-xs font-semibold text-n-amber-11"
                      >{{ week.count }}</span
                    >
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Tab: Insights de IA -->
        <div v-else-if="activeTab === 'insights'">
          <div v-if="insights && insights.length > 0" class="space-y-4">
            <div
              v-for="insight in insights"
              :key="insight.id"
              class="rounded-2xl border border-n-weak bg-n-alpha-1 overflow-hidden"
            >
              <!-- ── Card Header (always visible) ── -->
              <div class="p-5">
                <!-- Title row -->
                <div class="flex items-start justify-between gap-4">
                  <div class="flex-1 min-w-0">
                    <p class="text-base font-semibold text-n-slate-12 mb-1">
                      {{ periodLabel(insight) }}
                    </p>
                    <p class="text-sm text-n-slate-9 flex items-center gap-1.5">
                      <span class="i-lucide-message-square size-3.5" />
                      {{ insight.conversations_count }}
                      {{ t('CAPTAIN_REPORTS.INSIGHT.CONVERSATIONS') }}
                      <span class="text-n-slate-6">·</span>
                      {{ insight.messages_count }}
                      {{ t('CAPTAIN_REPORTS.INSIGHT.MESSAGES') }}
                    </p>
                  </div>
                  <span
                    class="inline-flex items-center rounded-full px-2.5 py-1 text-xs font-medium shrink-0"
                    :class="statusClass(insight.status)"
                  >
                    {{ statusLabel(insight.status) }}
                  </span>
                </div>

                <!-- Sentiment bar (always visible when data exists) -->
                <div v-if="sentimentOf(insight)" class="mt-4">
                  <div
                    class="flex h-1.5 rounded-full overflow-hidden bg-n-slate-3"
                  >
                    <div
                      class="bg-n-teal-9 transition-all duration-500"
                      :style="{
                        width: sentimentOf(insight).positivePercent + '%',
                      }"
                    />
                    <div
                      class="bg-n-ruby-9 transition-all duration-500"
                      :style="{
                        width: sentimentOf(insight).negativePercent + '%',
                      }"
                    />
                    <div
                      class="bg-n-slate-6 transition-all duration-500"
                      :style="{
                        width: sentimentOf(insight).neutralPercent + '%',
                      }"
                    />
                  </div>
                  <div class="flex gap-4 mt-2">
                    <span
                      class="flex items-center gap-1.5 text-xs text-n-teal-11"
                    >
                      <span
                        class="size-1.5 rounded-full bg-n-teal-9 inline-block"
                      />
                      {{ sentimentOf(insight).positivePercent }}%
                      {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_POSITIVE') }}
                    </span>
                    <span
                      class="flex items-center gap-1.5 text-xs text-n-ruby-11"
                    >
                      <span
                        class="size-1.5 rounded-full bg-n-ruby-9 inline-block"
                      />
                      {{ sentimentOf(insight).negativePercent }}%
                      {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_NEGATIVE') }}
                    </span>
                    <span
                      class="flex items-center gap-1.5 text-xs text-n-slate-10"
                    >
                      <span
                        class="size-1.5 rounded-full bg-n-slate-6 inline-block"
                      />
                      {{ sentimentOf(insight).neutralPercent }}%
                      {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_NEUTRAL') }}
                    </span>
                  </div>
                </div>

                <!-- Period summary -->
                <div
                  v-if="insight.payload && insight.payload.period_summary"
                  class="mt-3 text-sm text-n-slate-10 italic leading-relaxed"
                >
                  {{ insight.payload.period_summary }}
                </div>

                <!-- Top Topics (always visible) -->
                <div
                  v-if="insight.payload && insight.payload.top_topics?.length"
                  class="mt-4"
                >
                  <p
                    class="mb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                  >
                    {{ t('CAPTAIN_REPORTS.INSIGHT.TOP_TOPICS') }}
                  </p>
                  <div class="flex flex-wrap gap-1.5">
                    <span
                      v-for="topic in insight.payload.top_topics.slice(0, 5)"
                      :key="topic.topic"
                      class="inline-flex items-center gap-1 rounded-full bg-n-blue-2 px-2.5 py-1 text-xs text-n-blue-11 font-medium"
                    >
                      {{ topic.topic }}
                      <span class="font-bold text-n-blue-9"
                        >({{ topic.count }})</span
                      >
                    </span>
                  </div>
                </div>

                <!-- Expand/collapse toggle -->
                <div
                  v-if="hasExpandableContent(insight)"
                  class="mt-4 pt-3 border-t border-n-weak"
                >
                  <button
                    class="flex items-center gap-1.5 text-xs font-medium text-n-brand hover:opacity-80 transition-opacity"
                    @click="toggleInsight(insight.id)"
                  >
                    <span
                      class="size-3.5"
                      :class="
                        isExpanded(insight.id)
                          ? 'i-lucide-chevron-up'
                          : 'i-lucide-chevron-down'
                      "
                    />
                    {{
                      isExpanded(insight.id)
                        ? t('CAPTAIN_REPORTS.INSIGHT.HIDE_DETAILS')
                        : t('CAPTAIN_REPORTS.INSIGHT.SHOW_DETAILS')
                    }}
                  </button>
                </div>
              </div>

              <!-- ── Expanded Detail Sections ── -->
              <div
                v-if="isExpanded(insight.id) && insight.payload"
                class="border-t border-n-weak"
              >
                <!-- 2-column grid -->
                <div class="p-5 grid grid-cols-1 md:grid-cols-2 gap-3">
                  <!-- Most Requested Suites -->
                  <div
                    v-if="insight.payload.most_requested_suites?.length"
                    class="rounded-xl bg-n-alpha-2 p-4"
                  >
                    <p
                      class="flex items-center gap-1.5 mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                    >
                      <span class="i-lucide-building-2 size-3.5" />
                      {{ t('CAPTAIN_REPORTS.INSIGHT.MOST_REQUESTED_SUITES') }}
                    </p>
                    <div class="space-y-2">
                      <div
                        v-for="(
                          suite, idx
                        ) in insight.payload.most_requested_suites.slice(0, 5)"
                        :key="suite.suite"
                        class="flex items-center justify-between"
                      >
                        <div class="flex items-center gap-2 min-w-0">
                          <span
                            class="text-xs font-bold text-n-slate-7 w-4 shrink-0"
                            >{{ idx + 1 }}</span
                          >
                          <span
                            class="text-sm text-n-slate-11 truncate"
                            :title="suite.suite"
                            >{{ suite.suite }}</span
                          >
                        </div>
                        <span
                          class="text-xs font-medium text-n-slate-9 bg-n-slate-3 px-2 py-0.5 rounded-full shrink-0 ml-2"
                        >
                          {{ suite.count
                          }}{{ t('CAPTAIN_REPORTS.INSIGHT.TIMES') }}
                        </span>
                      </div>
                    </div>
                  </div>

                  <!-- Sentiment detail -->
                  <div
                    v-if="sentimentOf(insight)"
                    class="rounded-xl bg-n-alpha-2 p-4"
                  >
                    <p
                      class="flex items-center gap-1.5 mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                    >
                      <span class="i-lucide-activity size-3.5" />
                      {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT') }}
                    </p>
                    <div class="flex items-center gap-4 mb-3">
                      <div class="text-center">
                        <p class="text-xl font-bold text-n-teal-11">
                          {{ sentimentOf(insight).positive_count }}
                        </p>
                        <p class="text-xs text-n-slate-9">
                          {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_POSITIVE') }}
                        </p>
                      </div>
                      <div class="text-center">
                        <p class="text-xl font-bold text-n-ruby-11">
                          {{ sentimentOf(insight).negative_count }}
                        </p>
                        <p class="text-xs text-n-slate-9">
                          {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_NEGATIVE') }}
                        </p>
                      </div>
                      <div class="text-center">
                        <p class="text-xl font-bold text-n-slate-10">
                          {{ sentimentOf(insight).neutral_count }}
                        </p>
                        <p class="text-xs text-n-slate-9">
                          {{ t('CAPTAIN_REPORTS.INSIGHT.SENTIMENT_NEUTRAL') }}
                        </p>
                      </div>
                    </div>
                    <p
                      v-if="sentimentOf(insight).summary"
                      class="text-xs text-n-slate-10 italic leading-relaxed"
                    >
                      {{ sentimentOf(insight).summary }}
                    </p>
                  </div>

                  <!-- Praises -->
                  <div
                    v-if="insight.payload.highlights?.praises?.length"
                    class="rounded-xl bg-n-teal-2 p-4"
                  >
                    <p
                      class="flex items-center gap-1.5 mb-3 text-xs font-semibold uppercase tracking-wide text-n-teal-11"
                    >
                      <span class="i-lucide-thumbs-up size-3.5" />
                      {{ t('CAPTAIN_REPORTS.INSIGHT.PRAISES') }}
                    </p>
                    <ul class="space-y-2">
                      <li
                        v-for="(
                          praise, idx
                        ) in insight.payload.highlights.praises.slice(0, 4)"
                        :key="idx"
                        class="flex items-start gap-1.5 text-xs text-n-teal-11 leading-relaxed"
                      >
                        <span
                          class="i-lucide-message-circle size-3 shrink-0 mt-0.5 text-n-teal-9"
                        />
                        {{ praise }}
                      </li>
                    </ul>
                  </div>

                  <!-- Complaints -->
                  <div
                    v-if="insight.payload.highlights?.complaints?.length"
                    class="rounded-xl bg-n-ruby-2 p-4"
                  >
                    <p
                      class="flex items-center gap-1.5 mb-3 text-xs font-semibold uppercase tracking-wide text-n-ruby-11"
                    >
                      <span class="i-lucide-thumbs-down size-3.5" />
                      {{ t('CAPTAIN_REPORTS.INSIGHT.COMPLAINTS') }}
                    </p>
                    <ul class="space-y-2">
                      <li
                        v-for="(
                          complaint, idx
                        ) in insight.payload.highlights.complaints.slice(0, 4)"
                        :key="idx"
                        class="flex items-start gap-1.5 text-xs text-n-ruby-11 leading-relaxed"
                      >
                        <span
                          class="i-lucide-alert-circle size-3 shrink-0 mt-0.5 text-n-ruby-9"
                        />
                        {{ complaint }}
                      </li>
                    </ul>
                  </div>

                  <!-- Price Reactions -->
                  <div
                    v-if="insight.payload.price_reactions?.summary"
                    class="rounded-xl bg-n-alpha-2 p-4"
                  >
                    <p
                      class="flex items-center gap-1.5 mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-9"
                    >
                      <span class="i-lucide-tag size-3.5" />
                      {{ t('CAPTAIN_REPORTS.INSIGHT.PRICE_REACTIONS') }}
                    </p>
                    <p
                      class="text-xs text-n-slate-10 italic leading-relaxed mb-2"
                    >
                      {{ insight.payload.price_reactions.summary }}
                    </p>
                    <div
                      v-if="
                        insight.payload.price_reactions.objections_count > 0
                      "
                      class="flex items-center gap-1.5 mt-2"
                    >
                      <span
                        class="i-lucide-alert-triangle size-3 text-n-amber-9"
                      />
                      <span class="text-xs text-n-amber-11 font-medium">
                        {{ insight.payload.price_reactions.objections_count }}
                        {{ t('CAPTAIN_REPORTS.INSIGHT.PRICE_OBJECTIONS') }}
                      </span>
                    </div>
                  </div>
                </div>

                <!-- Full-width sections -->
                <div class="px-5 pb-5 space-y-3">
                  <!-- AI Failures -->
                  <div
                    v-if="insight.payload.ai_failures?.length"
                    class="rounded-xl bg-n-ruby-2 p-4"
                  >
                    <p
                      class="flex items-center gap-1.5 mb-3 text-xs font-semibold uppercase tracking-wide text-n-ruby-11"
                    >
                      <span class="i-lucide-bot size-3.5" />
                      {{ t('CAPTAIN_REPORTS.INSIGHT.AI_FAILURES') }}
                    </p>
                    <div class="space-y-2">
                      <div
                        v-for="(failure, idx) in insight.payload.ai_failures"
                        :key="idx"
                        class="flex items-start gap-2.5"
                      >
                        <span
                          class="text-xs font-mono font-bold text-n-ruby-9 shrink-0 mt-0.5 w-6"
                        >
                          {{ failure.frequency
                          }}{{ t('CAPTAIN_REPORTS.INSIGHT.TIMES') }}
                        </span>
                        <span class="text-xs text-n-ruby-11 leading-relaxed">
                          {{ failure.description }}
                        </span>
                      </div>
                    </div>
                  </div>

                  <!-- FAQ Gaps -->
                  <div
                    v-if="insight.payload.faq_gaps?.length"
                    class="rounded-xl bg-n-amber-2 p-4"
                  >
                    <div class="flex items-center justify-between mb-1">
                      <p
                        class="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-n-amber-11"
                      >
                        <span class="i-lucide-help-circle size-3.5" />
                        {{ t('CAPTAIN_REPORTS.INSIGHT.FAQ_GAPS') }}
                      </p>
                      <span
                        class="text-xs bg-n-amber-9 text-white px-2 py-0.5 rounded-full font-semibold"
                      >
                        {{ insight.payload.faq_gaps.length }}
                      </span>
                    </div>
                    <p class="text-xs text-n-amber-9 mb-3">
                      {{ t('CAPTAIN_REPORTS.INSIGHT.FAQ_GAPS_HINT') }}
                    </p>
                    <div class="space-y-1.5">
                      <div
                        v-for="(gap, idx) in insight.payload.faq_gaps"
                        :key="idx"
                        class="flex items-center gap-3"
                      >
                        <span class="text-xs text-n-amber-11 flex-1">{{
                          gap.question
                        }}</span>
                        <span
                          class="text-xs text-n-amber-9 shrink-0 font-medium"
                          >{{ gap.frequency
                          }}{{ t('CAPTAIN_REPORTS.INSIGHT.TIMES') }}</span
                        >
                        <button
                          class="shrink-0 text-xs font-medium text-n-amber-11 bg-n-amber-3 hover:bg-n-amber-4 px-2 py-0.5 rounded-full transition-colors"
                          @click="openQuickAddFaq(gap.question)"
                        >
                          {{ t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.BUTTON') }}
                        </button>
                      </div>
                    </div>
                  </div>

                  <!-- Recommendations -->
                  <div
                    v-if="insight.payload.recommendations?.length"
                    class="rounded-xl bg-n-teal-2 p-4"
                  >
                    <p
                      class="flex items-center gap-1.5 mb-3 text-xs font-semibold uppercase tracking-wide text-n-teal-11"
                    >
                      <span class="i-lucide-lightbulb size-3.5" />
                      {{ t('CAPTAIN_REPORTS.INSIGHT.RECOMMENDATIONS') }}
                    </p>
                    <div class="space-y-2">
                      <div
                        v-for="(rec, idx) in insight.payload.recommendations"
                        :key="idx"
                        class="flex items-start gap-2.5 p-2.5 rounded-lg bg-n-alpha-1"
                      >
                        <span
                          class="i-lucide-check-circle size-3.5 text-n-teal-9 shrink-0 mt-0.5"
                        />
                        <span class="text-xs text-n-teal-11 leading-relaxed">{{
                          rec
                        }}</span>
                      </div>
                    </div>
                  </div>
                </div>
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

  <!-- FAQ Quick-Add Modal -->
  <Teleport to="body">
    <div
      v-if="quickAddFaq.open"
      class="fixed inset-0 z-50 flex items-center justify-center bg-n-alpha-black-3 p-4"
      @click.self="closeQuickAddFaq"
    >
      <div
        class="w-full max-w-md rounded-2xl border border-n-weak bg-n-solid-1 p-6 shadow-xl"
      >
        <p class="mb-5 text-base font-semibold text-n-slate-12">
          {{ t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.TITLE') }}
        </p>
        <div class="space-y-4">
          <div>
            <label class="mb-1.5 block text-xs font-medium text-n-slate-9">
              {{ t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.QUESTION_LABEL') }}
            </label>
            <p
              class="w-full rounded-lg border border-n-weak bg-n-alpha-2 px-3 py-2 text-sm text-n-slate-11"
            >
              {{ quickAddFaq.question }}
            </p>
          </div>
          <div v-if="assistants && assistants.length > 1">
            <label class="mb-1.5 block text-xs font-medium text-n-slate-9">
              {{ t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.ASSISTANT_LABEL') }}
            </label>
            <select
              v-model="quickAddFaq.assistantId"
              class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            >
              <option :value="null" disabled>
                {{ t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.ASSISTANT_PLACEHOLDER') }}
              </option>
              <option
                v-for="assistant in assistants"
                :key="assistant.id"
                :value="assistant.id"
              >
                {{ assistant.name }}
              </option>
            </select>
          </div>
          <div>
            <label class="mb-1.5 block text-xs font-medium text-n-slate-9">
              {{ t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.ANSWER_LABEL') }}
            </label>
            <textarea
              v-model="quickAddFaq.answer"
              rows="4"
              class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-7 focus:outline-none focus:ring-2 focus:ring-n-brand"
              :placeholder="
                t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.ANSWER_PLACEHOLDER')
              "
            />
          </div>
        </div>
        <div class="mt-5 flex justify-end gap-2">
          <Button
            :label="t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.CANCEL')"
            color="slate"
            @click="closeQuickAddFaq"
          />
          <Button
            :label="t('CAPTAIN_REPORTS.FAQ_QUICK_ADD.SAVE')"
            icon="i-lucide-check"
            color="blue"
            :is-loading="quickAddFaq.saving"
            :disabled="!quickAddFaq.answer || !quickAddFaq.assistantId"
            @click="submitQuickAddFaq"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>
