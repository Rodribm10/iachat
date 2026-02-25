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
      return `/api/v1/accounts/${accountId.value}/inboxes/${props.inbox.id}/evolution${endpoint}`;
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
        const evolutionData = data.instance || {};

        const isEvolutionConnected =
          evolutionData.state === 'open' ||
          data.state === 'open' ||
          data.state === 'connected';

        const legacyStatus = data.status || data.state;
        const isLegacyConnected = ['open', 'connected', 'success'].includes(
          legacyStatus
        );

        isConnected.value = isEvolutionConnected || isLegacyConnected;
        statusMessage.value = evolutionData.state || legacyStatus || 'Unknown';

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
        // In evolution go, QR is typically returned as base64 in `qrcode` or `base64` property
        const qrcodeData =
          d.qrcode?.base64 ||
          d.base64 ||
          d.qrcode ||
          d.qr ||
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

    const disconnect = async () => {
      isLoading.value = true;
      try {
        await window.axios.post(getApiUrl('/disconnect'));
        useAlert(t('INBOX_MGMT.EDIT.EVOLUTION.DISCONNECT_SUCCESS'));
        isConnected.value = false;
        qrCode.value = '';
        fetchStatus();
      } catch (error) {
        useAlert(t('INBOX_MGMT.EDIT.EVOLUTION.DISCONNECT_ERROR'));
      } finally {
        isLoading.value = false;
      }
    };

    onMounted(() => {
      fetchStatus();
      // Only fetch QR code if not already connected
      if (!isConnected.value) {
        fetchQrCode();
      }
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
      accountId,
    };
  },
});
</script>

<template>
  <div class="mx-8 mt-6">
    <div class="bg-white p-6 rounded-lg border border-n-weak">
      <h3 class="text-lg font-medium text-n-slate-12 mb-4">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PROVIDERS.EVOLUTION') }}
        {{ `- ${$t('INBOX_MGMT.SETTINGS_POPUP.MESSENGER_CONFIG')}` }}
      </h3>

      <div v-if="accountId" class="flex flex-col items-center">
        <div v-if="isConnected" class="flex flex-col items-center">
          <div class="text-green-600 font-bold mb-4 flex items-center gap-2">
            <span class="i-woot-checkmark-circle text-2xl" />
            {{ $t('INBOX_MGMT.EDIT.EVOLUTION.CONNECTED') }}
          </div>
          <p class="text-n-slate-11 mb-4">
            {{ $t('INBOX_MGMT.EDIT.EVOLUTION.CONNECTED_DESC') }}
          </p>
          <NextButton
            color="ruby"
            :is-loading="isLoading"
            :label="$t('INBOX_MGMT.EDIT.EVOLUTION.DISCONNECT')"
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
              {{ $t('INBOX_MGMT.EDIT.EVOLUTION.SCAN_QR') }}
            </p>
          </div>

          <div v-else class="flex flex-col items-center mb-4">
            <p class="text-n-slate-11 mb-4">
              {{
                $t('INBOX_MGMT.EDIT.EVOLUTION.CONNECT_DESC') ||
                'Loading QR Code...'
              }}
            </p>
          </div>

          <div class="mt-4 text-xs text-n-slate-10">
            {{ $t('JASMINE.EVOLUTION.STATUS', { status: statusMessage }) }}
          </div>
        </div>
      </div>

      <div v-else class="text-red-600 p-4">
        {{ $t('JASMINE.EVOLUTION.ACCOUNT_ERROR') }}
      </div>
    </div>
  </div>
</template>
