<script>
import { computed, defineComponent, onMounted, onUnmounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const POLL_INTERVAL_MS = 5000;
const DEFAULT_QR_TTL_SECONDS = 60;
const MAX_QR_TTL_SECONDS = 180;

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
    const webhookConfigured = ref(false);
    let pollInterval;
    let qrExpiryTimer;

    const accountId = computed(
      () => store.getters.getCurrentAccountId || props.inbox.account_id
    );
    const apiUrl = suffix =>
      `/api/v1/accounts/${accountId.value}/inboxes/${props.inbox.id}/gowa${suffix}`;

    const stopPolling = () => {
      if (pollInterval) clearInterval(pollInterval);
      pollInterval = null;
    };

    const stopQrExpiryTimer = () => {
      if (qrExpiryTimer) clearTimeout(qrExpiryTimer);
      qrExpiryTimer = null;
    };

    const expireQrCode = () => {
      qrCode.value = '';
      stopPolling();
      stopQrExpiryTimer();
      statusMessage.value = t('INBOX_MGMT.EDIT.GOWA.QR_EXPIRED');
    };

    const startQrExpiryTimer = expiresIn => {
      stopQrExpiryTimer();
      const parsedTtl = Number(expiresIn);
      const ttl =
        Number.isFinite(parsedTtl) && parsedTtl > 0
          ? Math.min(parsedTtl, MAX_QR_TTL_SECONDS)
          : DEFAULT_QR_TTL_SECONDS;
      qrExpiryTimer = setTimeout(expireQrCode, ttl * 1000);
    };

    const ensureWebhook = async () => {
      if (webhookConfigured.value) return;

      try {
        await window.axios.put(apiUrl('/update_webhook'));
        webhookConfigured.value = true;
      } catch (error) {
        statusMessage.value =
          error.response?.data?.error ||
          t('INBOX_MGMT.EDIT.GOWA.WEBHOOK_ERROR');
      }
    };

    const fetchStatus = async () => {
      try {
        const { data } = await window.axios.get(apiUrl(''));
        const result = data.results || {};
        isConnected.value =
          result.is_connected === true && result.is_logged_in === true;
        if (!qrCode.value || isConnected.value) {
          statusMessage.value = result.state || data.message || '';
        }
        if (isConnected.value) {
          qrCode.value = '';
          stopPolling();
          stopQrExpiryTimer();
          await ensureWebhook();
        }
      } catch (error) {
        statusMessage.value = error.response?.data?.error || error.message;
      }
    };

    const fetchQrCode = async () => {
      const { data } = await window.axios.get(apiUrl('/qr'), {
        params: { timestamp: Date.now() },
      });
      if (!data.qrcode) {
        throw new Error(t('INBOX_MGMT.EDIT.GOWA.CONNECT_ERROR'));
      }

      qrCode.value = data.qrcode;
      statusMessage.value = t('INBOX_MGMT.EDIT.GOWA.WAITING_CONNECTION');
      startQrExpiryTimer(data.expires_in);
    };

    const startPolling = () => {
      if (pollInterval) return;
      pollInterval = setInterval(fetchStatus, POLL_INTERVAL_MS);
    };

    const connect = async () => {
      if (qrCode.value) return;

      isLoading.value = true;
      try {
        stopPolling();
        stopQrExpiryTimer();
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
        webhookConfigured.value = false;
        stopPolling();
        stopQrExpiryTimer();
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
    onUnmounted(() => {
      stopPolling();
      stopQrExpiryTimer();
    });

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
            :disabled="Boolean(qrCode)"
            :label="
              qrCode
                ? $t('INBOX_MGMT.EDIT.GOWA.WAITING')
                : $t('INBOX_MGMT.EDIT.GOWA.CONNECT')
            "
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
