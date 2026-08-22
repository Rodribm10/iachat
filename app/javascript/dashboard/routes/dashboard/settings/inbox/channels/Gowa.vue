<script setup>
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const router = useRouter();
const store = useStore();
const { t } = useI18n();

const gowaBaseUrl = ref('');
const gowaUsername = ref('');
const gowaPassword = ref('');
const inboxName = ref('');
const phoneNumber = ref('');
const isCreating = ref(false);

const isSubmitEnabled = computed(() => {
  return (
    gowaBaseUrl.value &&
    gowaUsername.value &&
    gowaPassword.value &&
    inboxName.value &&
    phoneNumber.value
  );
});

const createChannel = async () => {
  isCreating.value = true;
  try {
    const response = await store.dispatch('inboxes/createChannel', {
      channel: {
        type: 'whatsapp',
        provider: 'gowa',
        provider_config: {
          gowa_base_url: gowaBaseUrl.value.replace(/\/$/, ''),
        },
        gowa_username: gowaUsername.value,
        gowa_password: gowaPassword.value,
        phone_number: phoneNumber.value,
      },
      name: inboxName.value,
    });

    router.push({
      name: 'settings_inbox_show',
      params: { inboxId: response.id },
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        error?.message ||
        t('INBOX_MGMT.ADD.WHATSAPP.GOWA.ERROR_MESSAGE')
    );
  } finally {
    isCreating.value = false;
  }
};
</script>

<template>
  <div class="w-full max-w-2xl pb-12 mx-auto">
    <div class="mb-6">
      <h2 class="text-2xl font-bold text-n-slate-12">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.GOWA') }}
      </h2>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.GOWA_DESC') }}
      </p>
    </div>

    <form class="space-y-6" @submit.prevent="createChannel">
      <section
        class="grid grid-cols-1 gap-4 p-4 border rounded-xl border-n-strong bg-n-alpha-1"
      >
        <div>
          <label
            class="block mb-1 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.BASE_URL.LABEL') }}
          </label>
          <input
            v-model="gowaBaseUrl"
            type="url"
            class="w-full px-4 py-2 bg-white border rounded-lg outline-none border-n-strong focus:ring-2 focus:ring-n-brand"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.BASE_URL.PLACEHOLDER')
            "
            required
          />
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label
              class="block mb-1 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
            >
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.USERNAME.LABEL') }}
            </label>
            <input
              v-model="gowaUsername"
              type="text"
              autocomplete="username"
              class="w-full px-4 py-2 bg-white border rounded-lg outline-none border-n-strong focus:ring-2 focus:ring-n-brand"
              :placeholder="
                $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.USERNAME.PLACEHOLDER')
              "
              required
            />
          </div>
          <div>
            <label
              class="block mb-1 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
            >
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.PASSWORD.LABEL') }}
            </label>
            <input
              v-model="gowaPassword"
              type="password"
              autocomplete="current-password"
              class="w-full px-4 py-2 bg-white border rounded-lg outline-none border-n-strong focus:ring-2 focus:ring-n-brand"
              :placeholder="
                $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.PASSWORD.PLACEHOLDER')
              "
              required
            />
          </div>
        </div>
      </section>

      <section class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div>
          <label
            class="block mb-1 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
          </label>
          <input
            v-model="inboxName"
            type="text"
            class="w-full px-4 py-2 bg-white border rounded-lg outline-none border-n-strong focus:ring-2 focus:ring-n-brand"
            :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
            required
          />
        </div>
        <div>
          <label
            class="block mb-1 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.PHONE_NUMBER.LABEL') }}
          </label>
          <input
            v-model="phoneNumber"
            type="tel"
            inputmode="numeric"
            class="w-full px-4 py-2 bg-white border rounded-lg outline-none border-n-strong focus:ring-2 focus:ring-n-brand"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.PHONE_NUMBER.PLACEHOLDER')
            "
            required
          />
          <p class="mt-1 text-xs text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.GOWA.PHONE_NUMBER.HELP_TEXT') }}
          </p>
        </div>
      </section>

      <NextButton
        type="submit"
        color="blue"
        :is-loading="isCreating"
        :disabled="!isSubmitEnabled"
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.GOWA.SUBMIT_BUTTON')"
      />
    </form>
  </div>
</template>
