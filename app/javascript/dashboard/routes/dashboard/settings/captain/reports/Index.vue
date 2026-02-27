<script setup>
import { ref, onMounted } from 'vue';
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

const tabs = [{ key: 'insights' }, { key: 'operational' }];

onMounted(async () => {
  await store.dispatch('inboxes/get');
  await store.dispatch('captainReports/fetchInsights', {});
});

const onFilterChange = async event => {
  const value = event.target.value;
  selectedInboxId.value = value ? Number(value) : null;
  await store.dispatch('captainReports/fetchInsights', {
    inbox_id: selectedInboxId.value,
  });
};

const onGenerateInsight = async () => {
  try {
    await store.dispatch('captainReports/generateInsight', {
      inbox_id: selectedInboxId.value,
    });
    useAlert(t('CAPTAIN_REPORTS.GENERATE.SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN_REPORTS.GENERATE.ERROR'));
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
