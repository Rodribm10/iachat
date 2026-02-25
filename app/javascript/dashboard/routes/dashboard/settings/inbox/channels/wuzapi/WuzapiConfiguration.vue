<script>
// Use global axios (window.axios) which has interceptors for auth headers
import { defineComponent, ref, onMounted, onUnmounted, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default defineComponent({
  components: { NextButton },
  props: {
    inbox: {
      type: Object,
      required: true,
    },
  },
  setup(props) {
    const { t } = useI18n();
    const store = useStore();
    const isLoading = ref(false);
    const isConnected = ref(false);
    const qrCode = ref('');
    const statusMessage = ref('');
    let pollInterval = null;

    // Get accountId reliably from global store (preferred) or inbox prop
    const accountId = computed(() => {
      return store.getters.getCurrentAccountId || props.inbox.account_id;
    });

    // Helper for API URL
    const getApiUrl = endpoint => {
      if (!accountId.value) throw new Error('Account ID missing');
      return `/api/v1/accounts/${accountId.value}/inboxes/${props.inbox.id}/wuzapi${endpoint}`;
    };

    function stopPolling() {
      if (pollInterval) {
        clearInterval(pollInterval);
        pollInterval = null;
      }
    }

    async function fetchStatus() {
      if (!accountId.value) return;

      try {
        const response = await window.axios.get(getApiUrl(''));

        const data = response.data;
        const wuzapiData = data.data || {};

        const isWuzapiConnected =
          wuzapiData.connected === true && !!wuzapiData.jid;

        const legacyStatus = data.status || data.state;
        const isLegacyConnected = ['CONNECTED', 'inChat', 'success'].includes(
          legacyStatus
        );

        isConnected.value = isWuzapiConnected || isLegacyConnected;
        statusMessage.value = wuzapiData.details || legacyStatus || 'Unknown';

        if (isConnected.value) {
          qrCode.value = '';
          stopPolling();
        }
      } catch (error) {
        statusMessage.value =
          error.response?.data?.error || error.message || 'Check failed';
      }
    }

    /* eslint-disable no-use-before-define */
    function startPolling() {
      if (pollInterval) return;
      pollInterval = setInterval(async () => {
        await fetchStatus();
        if (pollInterval && !isConnected.value) {
          await fetchQrCode();
        }
      }, 5000);
    }

    async function fetchQrCode() {
      try {
        const response = await window.axios.get(getApiUrl('/qr'));
        const d = response.data;
        const qrcodeData =
          d.qrcode ||
          d.qr ||
          d.QRCode ||
          d.data?.qrcode ||
          d.data?.qr ||
          (typeof d.data === 'string' ? d.data : null);

        if (qrcodeData && qrcodeData.length > 20) {
          qrCode.value = qrcodeData;
          startPolling();
        } else {
          await fetchStatus();
          if (!isConnected.value) {
            statusMessage.value = 'QR Code not received and not connected.';
          }
        }
      } catch (error) {
        statusMessage.value =
          error.response?.data?.error || 'Failed to load QR';
      }
    }

    const handleConnect = async () => {
      if (!accountId.value) {
        useAlert('Error: Account ID missing');
        return;
      }

      isLoading.value = true;
      try {
        // 1. Call Connect
        const connectUrl = getApiUrl('/connect');
        await window.axios.post(connectUrl);
        // 2. Fetch QR
        await fetchQrCode();
      } catch (error) {
        useAlert(error.response?.data?.error || 'Connection failed');
      } finally {
        isLoading.value = false;
      }
    };

    const disconnect = async () => {
      isLoading.value = true;
      try {
        await window.axios.post(getApiUrl('/disconnect'));
        useAlert(t('INBOX_MGMT.EDIT.WUZAPI.DISCONNECT_SUCCESS'));
        isConnected.value = false;
        qrCode.value = '';
        fetchStatus();
      } catch (error) {
        useAlert(t('INBOX_MGMT.EDIT.WUZAPI.DISCONNECT_ERROR'));
      } finally {
        isLoading.value = false;
      }
    };

    const isLoadingWebhook = ref(false);
    const webhookInfo = ref(null);

    const fetchWebhookInfo = async () => {
      isLoadingWebhook.value = true;
      try {
        const response = await window.axios.get(getApiUrl('/webhook_info'));
        webhookInfo.value = response.data;
        useAlert('Webhook info fetched successfully');
      } catch (error) {
        useAlert(error.response?.data?.error || 'Failed to fetch webhook info');
      } finally {
        isLoadingWebhook.value = false;
      }
    };

    const updateWebhook = async () => {
      isLoadingWebhook.value = true;
      try {
        const response = await window.axios.put(getApiUrl('/update_webhook'));
        webhookInfo.value = {
          message: response.data.message,
          url: response.data.webhook_url,
        };
        useAlert('Webhook updated successfully');
      } catch (error) {
        useAlert(error.response?.data?.error || 'Failed to update webhook');
      } finally {
        isLoadingWebhook.value = false;
      }
    };

    onMounted(() => {
      fetchStatus();
    });

    onUnmounted(() => {
      stopPolling();
    });

    return {
      isLoading,
      isConnected,
      qrCode,
      statusMessage,
      fetchStatus,
      disconnect,
      handleConnect,
      accountId,
      isLoadingWebhook,
      webhookInfo,
      fetchWebhookInfo,
      updateWebhook,
    };
  },
});
</script>

<template>
  <div class="mx-8 mt-6">
    <div class="bg-white p-6 rounded-lg border border-n-weak">
      <h3 class="text-lg font-medium text-n-slate-12 mb-4">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.WUZAPI') }}
        {{ `- ${$t('INBOX_MGMT.SETTINGS_POPUP.MESSENGER_CONFIG')}` }}
      </h3>

      <div v-if="accountId" class="flex flex-col items-center">
        <div v-if="isConnected" class="flex flex-col items-center">
          <div class="text-green-600 font-bold mb-4 flex items-center gap-2">
            <span class="i-woot-checkmark-circle text-2xl" />
            {{ $t('INBOX_MGMT.EDIT.WUZAPI.CONNECTED') }}
          </div>
          <p class="text-n-slate-11 mb-4">
            {{ $t('INBOX_MGMT.EDIT.WUZAPI.CONNECTED_DESC') }}
          </p>
          <NextButton
            color="ruby"
            :is-loading="isLoading"
            :label="$t('INBOX_MGMT.EDIT.WUZAPI.DISCONNECT')"
            @click="disconnect"
          />
        </div>

        <div v-else class="flex flex-col items-center">
          <div v-if="qrCode" class="mb-4">
            <img
              :src="qrCode"
              alt="Whatsapp QR Code"
              class="w-64 h-64 border rounded"
            />
            <p class="text-center text-sm text-n-slate-11 mt-2">
              {{ $t('INBOX_MGMT.EDIT.WUZAPI.SCAN_QR') }}
            </p>
          </div>

          <div v-else class="flex flex-col items-center mb-4">
            <p class="text-n-slate-11 mb-4">
              {{
                $t('INBOX_MGMT.EDIT.WUZAPI.CONNECT_DESC') ||
                'Click to initiate connection'
              }}
            </p>
            <NextButton
              color="blue"
              :is-loading="isLoading"
              :label="
                $t('INBOX_MGMT.EDIT.WUZAPI.CONNECT') || 'Connect WhatsApp'
              "
              @click="handleConnect"
            />
          </div>

          <div class="mt-4 text-xs text-n-slate-10">
            {{ $t('JASMINE.WUZAPI.STATUS', { status: statusMessage }) }}
          </div>
        </div>
      </div>

      <div v-else class="text-red-600 p-4">
        {{ $t('JASMINE.WUZAPI.ACCOUNT_ERROR') }}
      </div>
      <div class="mt-8 pt-6 border-t border-n-weak w-full">
        <h4 class="text-md font-medium text-n-slate-12 mb-4">
          {{ $t('JASMINE.WUZAPI.WEBHOOK_SECTION') }}
        </h4>
        <div class="flex gap-4 mb-4">
          <NextButton
            icon="i-woot-refresh"
            :is-loading="isLoadingWebhook"
            :label="$t('JASMINE.WUZAPI.GET_WEBHOOK_INFO')"
            @click="fetchWebhookInfo"
          />
          <NextButton
            icon="i-woot-upload"
            :is-loading="isLoadingWebhook"
            :label="$t('JASMINE.WUZAPI.UPDATE_WEBHOOK')"
            @click="updateWebhook"
          />
        </div>

        <div
          v-if="webhookInfo"
          class="bg-n-alpha-1 p-4 rounded text-sm font-mono overflow-auto"
        >
          <pre>{{ JSON.stringify(webhookInfo, null, 2) }}</pre>
        </div>
      </div>
    </div>
  </div>
</template>
