<script>
import { computed, defineComponent, onMounted, onUnmounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default defineComponent({
  components: { NextButton },
  props: {
    inbox: { type: Object, required: true },
  },
  setup(props) {
    const { t } = useI18n();
    const store = useStore();
    const isLoading = ref(false);
    const isConnected = ref(false);
    const qrCode = ref('');
    const statusMessage = ref('');
    let pollInterval;

    const accountId = computed(
      () => store.getters.getCurrentAccountId || props.inbox.account_id
    );
    const apiUrl = suffix =>
      `/api/v1/accounts/${accountId.value}/inboxes/${props.inbox.id}/gowa${suffix}`;

    const stopPolling = () => {
      if (pollInterval) clearInterval(pollInterval);
      pollInterval = null;
    };

    const fetchStatus = async () => {
      try {
        const { data } = await window.axios.get(apiUrl(''));
        const result = data.results || {};
        isConnected.value =
          result.is_connected === true && result.is_logged_in === true;
        statusMessage.value = data.message || result.state || '';
        if (isConnected.value) {
          qrCode.value = '';
          stopPolling();
        }
      } catch (error) {
        statusMessage.value = error.response?.data?.error || error.message;
      }
    };

    const fetchQrCode = async () => {
      const { data } = await window.axios.get(apiUrl('/qr'));
      qrCode.value = data.qrcode || '';
      statusMessage.value = data.message || statusMessage.value;
    };

    const startPolling = () => {
      if (pollInterval) return;
      pollInterval = setInterval(fetchStatus, 5000);
    };

    const connect = async () => {
      isLoading.value = true;
      try {
        await fetchQrCode();
        startPolling();
      } catch (error) {
        useAlert(
          error.response?.data?.error || t('INBOX_MGMT.EDIT.GOWA.CONNECT_ERROR')
        );
      } finally {
        isLoading.value = false;
      }
    };

    const disconnect = async () => {
      isLoading.value = true;
      try {
        await window.axios.post(apiUrl('/disconnect'));
        isConnected.value = false;
        qrCode.value = '';
        useAlert(t('INBOX_MGMT.EDIT.GOWA.DISCONNECT_SUCCESS'));
      } catch (error) {
        useAlert(
          error.response?.data?.error ||
            t('INBOX_MGMT.EDIT.GOWA.DISCONNECT_ERROR')
        );
      } finally {
        isLoading.value = false;
      }
    };

    onMounted(fetchStatus);
    onUnmounted(stopPolling);

    return {
      connect,
      disconnect,
      isConnected,
      isLoading,
      qrCode,
      statusMessage,
    };
  },
});
</script>

<template>
  <section class="mx-8 mt-6">
    <div class="p-6 bg-white border rounded-lg border-n-weak">
      <h3 class="mb-4 text-lg font-medium text-n-slate-12">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.GOWA') }}
        {{ $t('INBOX_MGMT.SETTINGS_POPUP.MESSENGER_CONFIG') }}
      </h3>

      <div class="flex flex-col items-center text-center">
        <template v-if="isConnected">
          <span class="flex gap-2 items-center mb-3 font-bold text-green-600">
            <span class="text-2xl i-woot-checkmark-circle" />
            {{ $t('INBOX_MGMT.EDIT.GOWA.CONNECTED') }}
          </span>
          <p class="mb-4 text-n-slate-11">
            {{ $t('INBOX_MGMT.EDIT.GOWA.CONNECTED_DESC') }}
          </p>
          <NextButton
            color="ruby"
            :is-loading="isLoading"
            :label="$t('INBOX_MGMT.EDIT.GOWA.DISCONNECT')"
            @click="disconnect"
          />
        </template>

        <template v-else>
          <div v-if="qrCode" class="mb-4">
            <img
              :src="qrCode"
              :alt="$t('INBOX_MGMT.EDIT.GOWA.QR_ALT')"
              class="w-64 h-64 border rounded"
            />
            <p class="mt-2 text-sm text-n-slate-11">
              {{ $t('INBOX_MGMT.EDIT.GOWA.SCAN_QR') }}
            </p>
          </div>
          <p v-else class="mb-4 text-n-slate-11">
            {{ $t('INBOX_MGMT.EDIT.GOWA.CONNECT_DESC') }}
          </p>
          <NextButton
            color="blue"
            :is-loading="isLoading"
            :label="$t('INBOX_MGMT.EDIT.GOWA.CONNECT')"
            @click="connect"
          />
          <p v-if="statusMessage" class="mt-4 text-xs text-n-slate-10">
            {{ statusMessage }}
          </p>
        </template>
      </div>
    </div>
  </section>
</template>
