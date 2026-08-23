<script>
import { useAlert, useTrack } from 'dashboard/composables';
import BotMetrics from './components/BotMetrics.vue';
import ReportFilters from './components/ReportFilters.vue';
import { GROUP_BY_FILTER } from './constants';
import ReportContainer from './ReportContainer.vue';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import ReportHeader from './components/ReportHeader.vue';

export default {
  name: 'BotReports',
  components: {
    BotMetrics,
    ReportHeader,
    ReportFilters,
    ReportContainer,
  },
  data() {
    return {
      from: 0,
      to: 0,
      groupBy: GROUP_BY_FILTER[1],
      inboxId: null,
      reportKeys: {
        BOT_RESOLUTION_COUNT: 'bot_resolutions_count',
        BOT_HANDOFF_COUNT: 'bot_handoffs_count',
      },
      businessHours: false,
    };
  },
  computed: {
    requestPayload() {
      return {
        from: this.from,
        to: this.to,
        inboxId: this.inboxId,
      };
    },
  },
  mounted() {
    this.fetchInboxes();
  },
  methods: {
    fetchAllData() {
      this.fetchBotSummary();
      this.fetchChartData();
    },
    fetchInboxes() {
      this.$store.dispatch('inboxes/get');
    },
    fetchBotSummary() {
      try {
        this.$store.dispatch('fetchBotSummary', this.getRequestPayload());
      } catch {
        useAlert(this.$t('REPORT.SUMMARY_FETCHING_FAILED'));
      }
    },
    fetchChartData() {
      Object.keys(this.reportKeys).forEach(async key => {
        try {
          await this.$store.dispatch('fetchAccountReport', {
            metric: this.reportKeys[key],
            ...this.getRequestPayload(),
          });
        } catch {
          useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
        }
      });
    },
    getRequestPayload() {
      const { from, to, groupBy, businessHours, inboxId } = this;
      const payload = {
        from,
        to,
        groupBy: groupBy?.period,
        businessHours,
      };
      if (inboxId) {
        payload.type = 'inbox';
        payload.id = inboxId;
      }
      return payload;
    },
    onFilterChange({ from, to, groupBy, businessHours, inboxes }) {
      this.from = from;
      this.to = to;
      this.groupBy = groupBy;
      this.businessHours = businessHours;
      this.inboxId = inboxes?.id || null;
      this.fetchAllData();

      useTrack(REPORTS_EVENTS.FILTER_REPORT, {
        filterValue: {
          from,
          to,
          groupBy,
          businessHours,
          inboxId: this.inboxId,
        },
        reportType: 'bots',
      });
    },
  },
};
</script>

<template>
  <ReportHeader :header-title="$t('BOT_REPORTS.HEADER')" />
  <div class="flex flex-col gap-4">
    <ReportFilters
      filter-type="inboxes"
      show-group-by
      :show-business-hours="false"
      :navigate-on-entity-filter="false"
      @filter-change="onFilterChange"
    />

    <BotMetrics :filters="requestPayload" />
    <ReportContainer
      account-summary-key="getBotSummary"
      summary-fetching-key="getBotSummaryFetchingStatus"
      :group-by="groupBy"
      :report-keys="reportKeys"
      :from="from"
      :to="to"
      :business-hours="businessHours"
    />
  </div>
</template>
