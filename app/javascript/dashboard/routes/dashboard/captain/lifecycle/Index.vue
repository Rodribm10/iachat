<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const tabs = computed(() => [
  { name: 'captain_lifecycle_rules', label: t('CAPTAIN_LIFECYCLE.TABS.RULES') },
  {
    name: 'captain_lifecycle_settings',
    label: t('CAPTAIN_LIFECYCLE.TABS.SETTINGS'),
  },
  {
    name: 'captain_lifecycle_history',
    label: t('CAPTAIN_LIFECYCLE.TABS.HISTORY'),
  },
]);

const activeIndex = computed(() =>
  Math.max(
    0,
    tabs.value.findIndex(tab => tab.name === route.name)
  )
);

const handleTabChanged = tab => {
  router.push({ name: tab.name, params: route.params });
};
</script>

<template>
  <PageLayout
    :header-title="t('CAPTAIN_LIFECYCLE.HEADER')"
    :show-assistant-switcher="false"
    :show-pagination-footer="false"
    :show-know-more="false"
  >
    <div class="flex flex-col gap-4">
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeIndex"
        @tab-changed="handleTabChanged"
      />
      <router-view />
    </div>
  </PageLayout>
</template>
