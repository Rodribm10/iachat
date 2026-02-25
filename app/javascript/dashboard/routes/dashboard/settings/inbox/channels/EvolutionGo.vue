<script setup>
import { ref, computed, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const router = useRouter();
const store = useStore();
const { t } = useI18n();

const evolutionApiUrl = ref('');
const evolutionAdminToken = ref('');
const displayName = ref('');
const channelName = ref('');
const whatsappNumber = ref('');

const isAlwaysOnline = ref(true);
const isRejectCalls = ref(true);
const isMarkMessagesRead = ref(true);
const isIgnoreGroups = ref(false);
const isIgnoreStatus = ref(true);

const isCreating = ref(false);
const isTesting = ref(false);
const isConnectionTested = ref(false);

// Auto-generate channel name from display name (slugify-ish)
watch(displayName, newVal => {
  if (newVal) {
    channelName.value = newVal
      .toLowerCase()
      .trim()
      .replace(/[^\w\s-]/g, '')
      .replace(/[\s_-]+/g, '-')
      .replace(/^-+|-+$/g, '');
  }
});

const isSubmitEnabled = computed(() => {
  return (
    evolutionApiUrl.value &&
    evolutionAdminToken.value &&
    displayName.value &&
    whatsappNumber.value &&
    isConnectionTested.value
  );
});

const testConnection = async () => {
  isTesting.value = true;
  try {
    const accountId = store.getters.getCurrentAccountId;
    await window.axios.post(
      `/api/v1/accounts/${accountId}/evolution/test_connection`,
      {
        api_url: evolutionApiUrl.value,
        api_token: evolutionAdminToken.value,
      }
    );
    isConnectionTested.value = true;
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECT_SUCCESS'));
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error ||
      t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CONNECT_ERROR');
    useAlert(errorMessage);
    isConnectionTested.value = false;
  } finally {
    isTesting.value = false;
  }
};

const createChannel = async () => {
  isCreating.value = true;
  try {
    const payload = {
      channel: {
        type: 'whatsapp',
        provider: 'evolution',
        provider_config: {
          evolution_base_url: evolutionApiUrl.value.replace(/\/$/, ''),
          settings: {
            always_online: isAlwaysOnline.value,
            reject_call: isRejectCalls.value,
            read_messages: isMarkMessagesRead.value,
            ignore_groups: isIgnoreGroups.value,
            ignore_status: isIgnoreStatus.value,
          },
        },
        evolution_api_token: evolutionAdminToken.value,
        phone_number: whatsappNumber.value,
      },
      name: displayName.value,
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
  <div class="h-full w-full max-w-2xl mx-auto pb-12">
    <div class="mb-6">
      <h2 class="text-2xl font-bold text-n-slate-12">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.EVOLUTION') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.EVOLUTION_DESC') }}
      </p>
    </div>

    <form class="space-y-6" @submit.prevent="createChannel">
      <!-- API Config -->
      <div
        class="grid grid-cols-1 gap-4 p-4 border rounded-xl border-n-strong bg-n-alpha-1"
      >
        <div>
          <label
            class="block text-xs font-semibold mb-1 uppercase tracking-wider opacity-70"
          >
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.API_URL.LABEL') }}
            <span class="text-red-500">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.ASTERISK') }}
            </span>
          </label>
          <input
            v-model="evolutionApiUrl"
            type="url"
            class="w-full px-4 py-2 bg-white border rounded-lg border-n-strong focus:ring-2 focus:ring-blue-500 outline-none"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.API_URL.PLACEHOLDER')
            "
            required
            @input="isConnectionTested = false"
          />
        </div>

        <div>
          <label
            class="block text-xs font-semibold mb-1 uppercase tracking-wider opacity-70"
          >
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.API_TOKEN.LABEL') }}
            <span class="text-red-500">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.ASTERISK') }}
            </span>
          </label>
          <input
            v-model="evolutionAdminToken"
            type="password"
            class="w-full px-4 py-2 bg-white border rounded-lg border-n-strong focus:ring-2 focus:ring-blue-500 outline-none"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.API_TOKEN.PLACEHOLDER')
            "
            required
            @input="isConnectionTested = false"
          />
        </div>
      </div>

      <!-- Identity -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label
            class="block text-xs font-semibold mb-1 uppercase tracking-wider opacity-70"
          >
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.DISPLAY_NAME.LABEL') }}
            <span class="text-red-500">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.ASTERISK') }}
            </span>
          </label>
          <input
            v-model="displayName"
            type="text"
            class="w-full px-4 py-2 bg-white border rounded-lg border-n-strong focus:ring-2 focus:ring-blue-500 outline-none"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.DISPLAY_NAME.PLACEHOLDER')
            "
            required
          />
          <p class="mt-1 text-xs text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.DISPLAY_NAME.HELP_TEXT') }}
          </p>
        </div>

        <div>
          <label
            class="block text-xs font-semibold mb-1 uppercase tracking-wider opacity-70"
          >
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CHANNEL_NAME.LABEL') }}
            <span class="text-red-500">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.ASTERISK') }}
            </span>
          </label>
          <input
            v-model="channelName"
            type="text"
            class="w-full px-4 py-2 bg-n-alpha-1 border rounded-lg border-n-strong text-n-slate-10 outline-none cursor-not-allowed"
            readonly
          />
          <p class="mt-1 text-xs text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.CHANNEL_NAME.HELP_TEXT') }}
          </p>
        </div>
      </div>

      <div>
        <label
          class="block text-xs font-semibold mb-1 uppercase tracking-wider opacity-70"
        >
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.PHONE_NUMBER.LABEL') }}
          <span class="text-red-500">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.ASTERISK') }}
          </span>
        </label>
        <div class="flex items-center">
          <span
            class="px-3 py-2 bg-n-alpha-2 border border-r-0 border-n-strong rounded-l-lg text-lg"
          >
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.BRAZIL_FLAG') }}
          </span>
          <input
            v-model="whatsappNumber"
            type="text"
            class="w-full px-4 py-2 bg-white border rounded-r-lg border-n-strong focus:ring-2 focus:ring-blue-500 outline-none"
            :placeholder="
              $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.PHONE_NUMBER.PLACEHOLDER')
            "
            required
          />
        </div>
      </div>

      <!-- Instance Settings -->
      <div class="p-6 border rounded-xl border-n-strong bg-white shadow-sm">
        <h3 class="text-base font-bold text-n-slate-12 mb-4">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE_SETTINGS.TITLE') }}
        </h3>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-y-3 gap-x-6 text-sm">
          <label class="flex items-center space-x-3 cursor-pointer group">
            <input
              v-model="isAlwaysOnline"
              type="checkbox"
              class="w-4 h-4 rounded text-blue-600 border-n-strong focus:ring-blue-500"
            />
            <span
              class="text-n-slate-12 group-hover:text-blue-600 transition-colors"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE_SETTINGS.ALWAYS_ONLINE'
                )
              }}
            </span>
          </label>
          <label class="flex items-center space-x-3 cursor-pointer group">
            <input
              v-model="isRejectCalls"
              type="checkbox"
              class="w-4 h-4 rounded text-blue-600 border-n-strong focus:ring-blue-500"
            />
            <span
              class="text-n-slate-12 group-hover:text-blue-600 transition-colors"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE_SETTINGS.REJECT_CALLS'
                )
              }}
            </span>
          </label>
          <label class="flex items-center space-x-3 cursor-pointer group">
            <input
              v-model="isMarkMessagesRead"
              type="checkbox"
              class="w-4 h-4 rounded text-blue-600 border-n-strong focus:ring-blue-500"
            />
            <span
              class="text-n-slate-12 group-hover:text-blue-600 transition-colors"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE_SETTINGS.READ_MESSAGES'
                )
              }}
            </span>
          </label>
          <label class="flex items-center space-x-3 cursor-pointer group">
            <input
              v-model="isIgnoreGroups"
              type="checkbox"
              class="w-4 h-4 rounded text-blue-600 border-n-strong focus:ring-blue-500"
            />
            <span
              class="text-n-slate-12 group-hover:text-blue-600 transition-colors"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE_SETTINGS.IGNORE_GROUPS'
                )
              }}
            </span>
          </label>
          <div
            class="flex items-center space-x-3 cursor-pointer group col-span-2"
          >
            <label class="flex items-center space-x-3 cursor-pointer group">
              <input
                v-model="isIgnoreStatus"
                type="checkbox"
                class="w-4 h-4 rounded text-blue-600 border-n-strong focus:ring-blue-500"
              />
              <span
                class="text-n-slate-12 group-hover:text-blue-600 transition-colors"
              >
                {{
                  $t(
                    'INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.INSTANCE_SETTINGS.IGNORE_STATUS'
                  )
                }}
              </span>
            </label>
          </div>
        </div>
      </div>

      <!-- Help Section -->
      <div class="p-6 border rounded-xl border-n-strong bg-n-alpha-1">
        <h4 class="flex items-center text-sm font-bold text-n-slate-12 mb-4">
          <span class="mr-2">
            {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_INFO') }}
          </span>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.TITLE') }}
        </h4>
        <p class="text-xs text-n-slate-11 mb-4 leading-relaxed">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.HELP_TEXT_1') }}
        </p>
        <ul class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <li class="flex items-start">
            <span class="mr-2 mt-0.5 text-xs">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_STAR') }}
            </span>
            <div>
              <p class="text-xs font-semibold text-n-slate-12">
                {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_ROCKET') }}
                {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.FEATURE_1') }}
              </p>
            </div>
          </li>
          <li class="flex items-start">
            <span class="mr-2 mt-0.5 text-xs">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_STAR') }}
            </span>
            <div>
              <p class="text-xs font-semibold text-n-slate-12">
                {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_SHIELD') }}
                {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.FEATURE_2') }}
              </p>
            </div>
          </li>
          <li class="flex items-start">
            <span class="mr-2 mt-0.5 text-xs">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_STAR') }}
            </span>
            <div>
              <p class="text-xs font-semibold text-n-slate-12">
                {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_SYNC') }}
                {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.FEATURE_3') }}
              </p>
            </div>
          </li>
          <li class="flex items-start">
            <span class="mr-2 mt-0.5 text-xs">
              {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_STAR') }}
            </span>
            <div>
              <p class="text-xs font-semibold text-n-slate-12">
                {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_CHART') }}
                {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.FEATURE_4') }}
              </p>
            </div>
          </li>
        </ul>
      </div>

      <!-- Warning -->
      <div
        v-if="!isConnectionTested"
        class="p-4 bg-yellow-50 border border-yellow-200 rounded-xl flex items-center space-x-3"
      >
        <span class="text-xl">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.HELP.ICON_WARNING') }}
        </span>
        <p class="text-xs text-yellow-800 font-medium">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.TEST_CONNECTION_BANNER') }}
        </p>
      </div>

      <div
        class="flex items-center justify-between pt-4 border-t border-n-strong"
      >
        <NextButton
          :is-loading="isTesting"
          type="button"
          outline
          :label="$t('INBOX_MGMT.ADD.WHATSAPP.EVOLUTION.TEST_CONNECTION')"
          @click="testConnection"
        />

        <div class="flex space-x-3">
          <NextButton
            type="button"
            outline
            :label="$t('INBOX_MGMT.ADD.WHATSAPP.CANCEL')"
            @click="router.back()"
          />
          <NextButton
            :is-loading="isCreating"
            :disabled="!isSubmitEnabled"
            type="submit"
            solid
            blue
            :label="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
          />
        </div>
      </div>
    </form>
  </div>
</template>

<style scoped>
.cursor-not-allowed {
  cursor: not-allowed;
}
</style>
