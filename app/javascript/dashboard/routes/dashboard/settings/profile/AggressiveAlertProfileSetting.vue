<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();

// Default true — só trata como false se estiver explicitamente como false.
const isEnabled = computed({
  get() {
    return uiSettings.value?.aggressive_alert_enabled !== false;
  },
  set(value) {
    updateUISettings({ aggressive_alert_enabled: value });
  },
});
</script>

<template>
  <div
    class="border border-solid rounded-lg border-n-weak p-4 bg-n-solid-1 flex items-start gap-4"
  >
    <div class="flex-1">
      <h4 class="text-base font-semibold text-n-slate-12 mb-1">
        {{ t('PROFILE_SETTINGS.FORM.AGGRESSIVE_ALERT.TITLE') }}
      </h4>
      <p class="text-sm text-n-slate-11 leading-normal">
        {{ t('PROFILE_SETTINGS.FORM.AGGRESSIVE_ALERT.NOTE') }}
      </p>
    </div>
    <div class="pt-1">
      <Switch v-model="isEnabled" />
    </div>
  </div>
</template>
