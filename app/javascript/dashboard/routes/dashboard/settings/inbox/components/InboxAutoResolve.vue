<script>
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import SettingsSection from 'dashboard/components/SettingsSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    SettingsSection,
    NextButton,
  },
  props: {
    inbox: {
      type: Object,
      required: true,
    },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      autoResolveDuration: null,
      isUpdating: false,
    };
  },
  mounted() {
    this.autoResolveDuration = this.inbox.auto_resolve_duration;
  },
  methods: {
    async updateInbox() {
      try {
        this.isUpdating = true;
        await this.$store.dispatch('inboxes/updateInbox', {
          id: this.inbox.id,
          auto_resolve_duration: this.autoResolveDuration,
        });
        useAlert(this.$t('INBOX_MGMT.EDIT.API.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.EDIT.API.ERROR_MESSAGE'));
      } finally {
        this.isUpdating = false;
      }
    },
  },
};
</script>

<template>
  <div class="mx-8">
    <SettingsSection
      :title="$t('GENERAL_SETTINGS.FORM.AUTO_RESOLVE.TITLE')"
      :sub-title="$t('GENERAL_SETTINGS.FORM.AUTO_RESOLVE.NOTE')"
      :show-border="false"
    >
      <div class="flex flex-col gap-1 items-start mb-4">
        <label class="mb-0.5 text-sm font-medium text-n-slate-12">
          {{ $t('GENERAL_SETTINGS.FORM.AUTO_RESOLVE.DURATION.LABEL') }}
        </label>
        <div class="w-full">
          <input
            v-model="autoResolveDuration"
            type="number"
            class="input-group"
            min="0"
            :placeholder="
              $t('GENERAL_SETTINGS.FORM.AUTO_RESOLVE.DURATION.PLACEHOLDER')
            "
          />
          <p class="text-sm text-n-slate-11 mt-1">
            {{ $t('GENERAL_SETTINGS.FORM.AUTO_RESOLVE.DURATION.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <div class="flex gap-2">
        <NextButton
          type="submit"
          :is-loading="isUpdating"
          :label="$t('GENERAL_SETTINGS.FORM.AUTO_RESOLVE.UPDATE_BUTTON')"
          @click="updateInbox"
        />
      </div>
    </SettingsSection>
  </div>
</template>
