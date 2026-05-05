<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import BuilderChat from './BuilderChat.vue';
import BuilderVerification from './BuilderVerification.vue';

const { t } = useI18n();

const tabs = computed(() => [
  { label: t('CAPTAIN_HERMES_BUILDER.TAB_CHAT'), key: 'chat' },
  { label: t('CAPTAIN_HERMES_BUILDER.TAB_VERIFY'), key: 'verification' },
]);

const activeIndex = ref(0);

const handleTabChanged = tab => {
  activeIndex.value = tabs.value.findIndex(item => item.key === tab.key);
};
</script>

<template>
  <PageLayout
    :title="t('CAPTAIN_HERMES_BUILDER.TITLE')"
    :description="t('CAPTAIN_HERMES_BUILDER.DESCRIPTION')"
  >
    <div class="builder-tabs">
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeIndex"
        @tab-changed="handleTabChanged"
      />
    </div>
    <div class="builder-panels">
      <BuilderChat v-show="activeIndex === 0" />
      <BuilderVerification v-show="activeIndex === 1" />
    </div>
  </PageLayout>
</template>

<style scoped lang="scss">
.builder-tabs {
  margin-bottom: 16px;
}

.builder-panels {
  display: flex;
  flex-direction: column;
}
</style>
