<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';

const { t } = useI18n();
// Default true — quando account ainda não carregou, assume ligado.
const isEnabled = ref(true);

const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    const settings = currentAccount.value?.settings || {};
    // Só trata como false se explicitamente false; qualquer outro valor = ligado.
    isEnabled.value = settings.aggressive_alert_enabled !== false;
  },
  { deep: true, immediate: true }
);

const toggle = async () => {
  try {
    await updateAccount({
      aggressive_alert_enabled: isEnabled.value,
    });
    useAlert(t('GENERAL_SETTINGS.FORM.AGGRESSIVE_ALERT.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.AGGRESSIVE_ALERT.API.ERROR'));
  }
};
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.AGGRESSIVE_ALERT.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.AGGRESSIVE_ALERT.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch v-model="isEnabled" @change="toggle" />
      </div>
    </template>
  </SectionLayout>
</template>
