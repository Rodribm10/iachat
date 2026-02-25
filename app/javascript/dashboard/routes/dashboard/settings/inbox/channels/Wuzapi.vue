<script setup>
import { ref, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const router = useRouter();
const store = useStore();
const { t } = useI18n();

const wuzapiBaseUrl = ref('');
const wuzapiAdminToken = ref('');
const inboxName = ref('');
const phoneNumber = ref('');
const autoCreateUser = ref(true);
const isCreating = ref(false);

const isSubmitEnabled = computed(() => {
  return (
    wuzapiBaseUrl.value &&
    wuzapiAdminToken.value &&
    inboxName.value &&
    phoneNumber.value
  );
});

const createChannel = async () => {
  isCreating.value = true;
  try {
    const payload = {
      channel: {
        type: 'whatsapp',
        provider: 'wuzapi',
        provider_config: {
          wuzapi_base_url: wuzapiBaseUrl.value.replace(/\/$/, ''),
          wuzapi_admin_token: wuzapiAdminToken.value,
          auto_create_user: autoCreateUser.value,
        },
        phone_number: phoneNumber.value,
      },
      name: inboxName.value,
    };

    const response = await store.dispatch('inboxes/createChannel', payload);
    router.push({
      name: 'settings_inbox_show',
      params: { inboxId: response.id },
    });
  } catch (error) {
    const errorMessage =
      error?.response?.data?.message ||
      error?.message ||
      t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  } finally {
    isCreating.value = false;
  }
};
</script>

<template>
  <div class="h-full w-full">
    <div class="mb-4">
      <h2 class="text-xl font-medium text-n-slate-12">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WUZAPI') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WUZAPI_DESC') }}
      </p>
    </div>

    <form class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannel">
      <div class="w-full mb-4">
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.WUZAPI.BASE_URL.LABEL') }}
        </label>
        <input
          v-model="wuzapiBaseUrl"
          type="url"
          class="w-full px-3 py-2 border rounded-md border-n-strong"
          :placeholder="
            $t('INBOX_MGMT.ADD.WHATSAPP.WUZAPI.BASE_URL.PLACEHOLDER')
          "
          required
        />
        <p class="mt-1 text-xs text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.WUZAPI.BASE_URL.HELP_TEXT') }}
        </p>
      </div>

      <div class="w-full mb-4">
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.WUZAPI.ADMIN_TOKEN.LABEL') }}
        </label>
        <input
          v-model="wuzapiAdminToken"
          type="password"
          class="w-full px-3 py-2 border rounded-md border-n-strong"
          :placeholder="
            $t('INBOX_MGMT.ADD.WHATSAPP.WUZAPI.ADMIN_TOKEN.PLACEHOLDER')
          "
          required
        />
      </div>

      <div class="w-full mb-4">
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        </label>
        <input
          v-model="inboxName"
          type="text"
          class="w-full px-3 py-2 border rounded-md border-n-strong"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          required
        />
      </div>

      <div class="w-full mb-4">
        <label class="block text-sm font-medium text-n-slate-12 mb-1">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        </label>
        <input
          v-model="phoneNumber"
          type="text"
          class="w-full px-3 py-2 border rounded-md border-n-strong"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          required
        />
      </div>

      <div class="w-full mb-4">
        <label class="flex items-center space-x-2">
          <input
            v-model="autoCreateUser"
            type="checkbox"
            class="rounded border-n-strong"
          />
          <span class="text-sm text-n-slate-12">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.WUZAPI.AUTO_CREATE_USER.LABEL') }}
          </span>
        </label>
      </div>

      <div class="w-full mt-4">
        <NextButton
          :is-loading="isCreating"
          :disabled="!isSubmitEnabled"
          type="submit"
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
        />
      </div>
    </form>
  </div>
</template>
