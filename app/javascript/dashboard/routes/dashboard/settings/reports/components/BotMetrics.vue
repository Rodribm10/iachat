<script setup>
import { ref, watch, onMounted } from 'vue';
import ReportMetricCard from './ReportMetricCard.vue';
import ReportsAPI from 'dashboard/api/reports';

const props = defineProps({
  filters: {
    type: Object,
    required: true,
  },
});

const conversationCount = ref('0');
const messageCount = ref('0');
const botResolutionRate = ref('0');
const humanTransferRate = ref('0');
const botResolutionsCount = ref('0');
const autoHandoffsCount = ref('0');
const manualTakeoversCount = ref('0');

const formatToPercent = value => {
  return value ? `${value}%` : '--';
};

const fetchMetrics = () => {
  if (!props.filters.to || !props.filters.from) {
    return;
  }
  ReportsAPI.getBotMetrics(props.filters).then(response => {
    conversationCount.value = response.data.conversation_count.toLocaleString();
    messageCount.value = response.data.message_count.toLocaleString();
    botResolutionRate.value = response.data.resolution_rate.toString();
    humanTransferRate.value = response.data.handoff_rate.toString();
    botResolutionsCount.value = (
      response.data.bot_resolutions_count || 0
    ).toLocaleString();
    autoHandoffsCount.value = (
      response.data.auto_handoffs_count || 0
    ).toLocaleString();
    manualTakeoversCount.value = (
      response.data.manual_takeovers_count || 0
    ).toLocaleString();
  });
};

watch(() => props.filters, fetchMetrics, { deep: true });

onMounted(fetchMetrics);
</script>

<template>
  <div class="flex flex-col gap-4">
    <div
      class="flex flex-wrap mx-0 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
    >
      <ReportMetricCard
        :label="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.LABEL')"
        :info-text="$t('BOT_REPORTS.METRIC.TOTAL_CONVERSATIONS.TOOLTIP')"
        :value="conversationCount"
        class="flex-1"
      />
      <ReportMetricCard
        :label="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.LABEL')"
        :info-text="$t('BOT_REPORTS.METRIC.TOTAL_RESPONSES.TOOLTIP')"
        :value="messageCount"
        class="flex-1"
      />
      <ReportMetricCard
        :label="$t('BOT_REPORTS.METRIC.RESOLUTION_RATE.LABEL')"
        :info-text="$t('BOT_REPORTS.METRIC.RESOLUTION_RATE.TOOLTIP')"
        :value="formatToPercent(botResolutionRate)"
        class="flex-1"
      />
      <ReportMetricCard
        :label="$t('BOT_REPORTS.METRIC.HANDOFF_RATE.LABEL')"
        :info-text="$t('BOT_REPORTS.METRIC.HANDOFF_RATE.TOOLTIP')"
        :value="formatToPercent(humanTransferRate)"
        class="flex-1"
      />
    </div>

    <div
      class="flex flex-wrap mx-0 shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 px-6 py-5"
    >
      <ReportMetricCard
        :label="$t('BOT_REPORTS.METRIC.BOT_RESOLUTIONS.LABEL')"
        :info-text="$t('BOT_REPORTS.METRIC.BOT_RESOLUTIONS.TOOLTIP')"
        :value="botResolutionsCount"
        class="flex-1"
      />
      <ReportMetricCard
        :label="$t('BOT_REPORTS.METRIC.AUTO_HANDOFFS.LABEL')"
        :info-text="$t('BOT_REPORTS.METRIC.AUTO_HANDOFFS.TOOLTIP')"
        :value="autoHandoffsCount"
        class="flex-1"
      />
      <ReportMetricCard
        :label="$t('BOT_REPORTS.METRIC.MANUAL_TAKEOVERS.LABEL')"
        :info-text="$t('BOT_REPORTS.METRIC.MANUAL_TAKEOVERS.TOOLTIP')"
        :value="manualTakeoversCount"
        class="flex-1"
      />
    </div>
  </div>
</template>
