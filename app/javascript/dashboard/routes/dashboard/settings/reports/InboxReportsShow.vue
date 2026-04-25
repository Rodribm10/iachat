<script setup>
import { ref } from 'vue';
import { useRoute } from 'vue-router';
import { useFunctionGetter } from 'dashboard/composables/store';

import WootReports from './components/WootReports.vue';
import InboxLeadsReport from './components/InboxLeadsReport.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const route = useRoute();
const inbox = useFunctionGetter('inboxes/getInboxById', route.params.id);

const TABS = {
  OVERVIEW: 'overview',
  LEADS: 'leads',
};

const activeTab = ref(TABS.OVERVIEW);
</script>

<template>
  <div v-if="inbox.id" class="flex flex-col w-full">
    <div class="flex items-center gap-6 px-6 pt-4 border-b border-n-weak">
      <button
        type="button"
        class="py-3 text-sm font-medium border-b-2 transition-colors"
        :class="
          activeTab === TABS.OVERVIEW
            ? 'border-n-brand text-n-brand'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="activeTab = TABS.OVERVIEW"
      >
        {{ $t('INBOX_REPORTS.TABS.OVERVIEW') }}
      </button>
      <button
        type="button"
        class="py-3 text-sm font-medium border-b-2 transition-colors"
        :class="
          activeTab === TABS.LEADS
            ? 'border-n-brand text-n-brand'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="activeTab = TABS.LEADS"
      >
        {{ $t('INBOX_REPORTS.TABS.LEADS') }}
      </button>
    </div>

    <div class="px-6 py-4">
      <WootReports
        v-if="activeTab === TABS.OVERVIEW"
        :key="`overview-${inbox.id}`"
        type="inbox"
        getter-key="inboxes/getInboxes"
        action-key="inboxes/get"
        :selected-item="inbox"
        :download-button-label="$t('INBOX_REPORTS.DOWNLOAD_INBOX_REPORTS')"
        :report-title="$t('INBOX_REPORTS.HEADER')"
        has-back-button
      />
      <InboxLeadsReport
        v-else-if="activeTab === TABS.LEADS"
        :key="`leads-${inbox.id}`"
        :inbox-id="inbox.id"
      />
    </div>
  </div>
  <div v-else class="w-full py-20">
    <Spinner class="mx-auto" />
  </div>
</template>
