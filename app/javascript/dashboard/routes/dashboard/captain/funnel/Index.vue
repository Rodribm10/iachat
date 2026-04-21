<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import funnelApi from 'dashboard/api/captain/funnel';

const { t } = useI18n();
const periodDays = ref(30);
const report = ref(null);
const loading = ref(false);

const SUITE_ORDER = ['Alexa', 'Stilo', 'Hidromassagem'];

async function load() {
  loading.value = true;
  try {
    const { data } = await funnelApi.get(periodDays.value);
    report.value = data;
  } catch (err) {
    useAlert(t('CAPTAIN_FUNNEL.LOAD_ERROR'));
  } finally {
    loading.value = false;
  }
}

const byDataSuite = computed(() => {
  if (!report.value?.by_suite) return [];
  return SUITE_ORDER.filter(s => report.value.by_suite[s]).map(s => ({
    name: s,
    stages: report.value.by_suite[s],
  }));
});

const topDropOff = computed(() => {
  const d = report.value?.top_drop_off;
  if (!d) return null;
  return {
    ...d,
    from_label: t(`CAPTAIN_FUNNEL.STAGES.${d.from}`),
    to_label: t(`CAPTAIN_FUNNEL.STAGES.${d.to}`),
  };
});

function fmtPct(v) {
  if (v === null || v === undefined) return '—';
  return `${(v * 100).toFixed(1)}%`;
}

function barWidth(count, maxCount) {
  if (!maxCount) return '0%';
  return `${Math.max(4, (count / maxCount) * 100)}%`;
}

function stageLabel(key) {
  return t(`CAPTAIN_FUNNEL.STAGES.${key}`);
}

onMounted(load);
</script>

<template>
  <PageLayout
    :header-title="t('CAPTAIN_FUNNEL.HEADER')"
    :show-assistant-switcher="false"
    :show-pagination-footer="false"
    :is-empty="false"
    :is-fetching="false"
  >
    <template #body>
      <div class="flex flex-col gap-6 py-4">
        <div class="flex items-center justify-between gap-3">
          <p class="text-sm text-n-slate-11 max-w-xl">
            {{ t('CAPTAIN_FUNNEL.DESC') }}
          </p>
          <div class="flex items-center gap-2">
            <select
              v-model.number="periodDays"
              class="rounded-md border border-n-weak bg-transparent text-sm px-2 py-1"
              @change="load"
            >
              <option :value="7">{{ t('CAPTAIN_FUNNEL.PERIOD_7') }}</option>
              <option :value="30">{{ t('CAPTAIN_FUNNEL.PERIOD_30') }}</option>
              <option :value="60">{{ t('CAPTAIN_FUNNEL.PERIOD_60') }}</option>
              <option :value="90">{{ t('CAPTAIN_FUNNEL.PERIOD_90') }}</option>
            </select>
            <Button
              variant="ghost"
              icon="i-lucide-refresh-cw"
              size="xs"
              :is-loading="loading"
              @click="load"
            />
          </div>
        </div>

        <div v-if="loading" class="text-sm text-n-slate-11 py-6">
          {{ t('CAPTAIN_FUNNEL.LOADING') }}
        </div>

        <template v-else-if="report && report.total_conversations_analyzed > 0">
          <div
            v-if="topDropOff && topDropOff.lost > 0"
            class="rounded-xl border border-n-amber-7 bg-n-amber-3 p-4"
          >
            <div class="text-xs uppercase tracking-wide text-n-amber-11 mb-1">
              {{ t('CAPTAIN_FUNNEL.INSIGHT_LABEL') }}
            </div>
            <div class="text-n-amber-12">
              {{
                t('CAPTAIN_FUNNEL.INSIGHT_FULL', {
                  lost: topDropOff.lost,
                  from: topDropOff.from_label,
                  to: topDropOff.to_label,
                  pct: fmtPct(topDropOff.drop_pct),
                })
              }}
            </div>
          </div>

          <div
            class="rounded-xl border border-n-weak bg-n-alpha-black2 p-6 shadow-sm"
          >
            <h2 class="text-lg font-semibold text-n-slate-12 mb-4">
              {{
                t('CAPTAIN_FUNNEL.FUNNEL_TITLE').replace(
                  '{count}',
                  report.total_conversations_analyzed
                )
              }}
            </h2>

            <div class="flex flex-col gap-3">
              <div
                v-for="(stage, idx) in report.funnel"
                :key="stage.key"
                class="flex items-center gap-3"
              >
                <div class="w-40 text-sm text-n-slate-11">
                  {{ stageLabel(stage.key) }}
                </div>
                <div class="flex-1 relative h-8 bg-n-alpha-black1 rounded">
                  <div
                    class="absolute left-0 top-0 h-full rounded bg-gradient-to-r from-n-brand/70 to-n-brand transition-all"
                    :style="{
                      width: barWidth(stage.count, report.funnel[0].count),
                    }"
                  />
                  <div
                    class="relative h-full flex items-center px-3 text-sm font-semibold text-n-slate-12"
                  >
                    {{ stage.count }}
                  </div>
                </div>
                <div class="w-20 text-right text-xs text-n-slate-11">
                  <template v-if="idx > 0">
                    {{ fmtPct(stage.conversion) }}
                  </template>
                </div>
              </div>
            </div>
          </div>

          <div
            v-if="byDataSuite.length > 0"
            class="rounded-xl border border-n-weak bg-n-alpha-black2 p-6 shadow-sm"
          >
            <h2 class="text-lg font-semibold text-n-slate-12 mb-4">
              {{ t('CAPTAIN_FUNNEL.BY_SUITE_TITLE') }}
            </h2>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="text-xs text-n-slate-11 uppercase tracking-wide">
                  <tr class="border-b border-n-weak">
                    <th class="text-left py-2 px-2">
                      {{ t('CAPTAIN_FUNNEL.BY_SUITE_HEADER') }}
                    </th>
                    <th
                      v-for="stage in report.funnel"
                      :key="stage.key"
                      class="text-right py-2 px-2"
                    >
                      {{ stageLabel(stage.key) }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="s in byDataSuite"
                    :key="s.name"
                    class="border-b border-n-weak last:border-b-0"
                  >
                    <td class="py-2 px-2 font-medium text-n-slate-12">
                      {{ s.name }}
                    </td>
                    <td
                      v-for="stage in s.stages"
                      :key="stage.key"
                      class="py-2 px-2 text-right text-n-slate-11"
                    >
                      {{ stage.count }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="text-xs text-n-slate-11 mt-3">
              {{ t('CAPTAIN_FUNNEL.BY_SUITE_FOOTER') }}
            </p>
          </div>
        </template>

        <div
          v-else-if="report"
          class="text-sm text-n-slate-11 py-6 text-center"
        >
          {{ t('CAPTAIN_FUNNEL.EMPTY') }}
        </div>
      </div>
    </template>
  </PageLayout>
</template>
