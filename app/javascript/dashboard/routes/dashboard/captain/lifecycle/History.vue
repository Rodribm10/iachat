<script setup>
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <div class="p-6">
    <h2 class="text-lg font-semibold">
      {{ t('CAPTAIN_LIFECYCLE.TABS.HISTORY') }}
    </h2>
    <!-- Implementation in Task 13 -->
  </div>
</template>
