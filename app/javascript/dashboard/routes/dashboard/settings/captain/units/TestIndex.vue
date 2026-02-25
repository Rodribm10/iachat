<script>
import SettingsLayout from '../../SettingsLayout.vue';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';

export default {
  name: 'TestUnitsIndex',
  components: {
    SettingsLayout,
    BaseSettingsHeader,
  },
};
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        :title="$t('CAPTAIN_SETTINGS.UNITS.TEST.HEADER_TITLE')"
        :description="$t('CAPTAIN_SETTINGS.UNITS.TEST.HEADER_DESCRIPTION')"
      />
    </template>

    <template #body>
      <div class="p-8">
        {{ $t('CAPTAIN_SETTINGS.UNITS.TEST.BODY_TEXT') }}
      </div>
    </template>
  </SettingsLayout>
</template>
