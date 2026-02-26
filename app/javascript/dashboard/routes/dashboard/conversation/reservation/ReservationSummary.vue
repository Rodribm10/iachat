<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

const props = defineProps({
  marker: {
    type: Object,
    default: () => ({}),
  },
});

const store = useStore();
const { t } = useI18n();

const reservation = ref(null);
const isLoading = ref(false);

const reservationId = computed(() => props.marker?.reservation_id);
const hasMarker = computed(() => !!props.marker?.visible);
const pixValue = computed(
  () => reservation.value?.pix_copy_paste || props.marker?.pix_copy_paste
);

const fetchReservation = async () => {
  if (!reservationId.value) {
    reservation.value = null;
    return;
  }

  isLoading.value = true;
  try {
    const response = await store.dispatch(
      'captainReservations/show',
      reservationId.value
    );
    reservation.value = response?.id ? response : null;
  } finally {
    isLoading.value = false;
  }
};

watch(reservationId, fetchReservation, { immediate: true });

const formatMoney = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(Number(value || 0));

const formatDateTime = value => {
  if (!value) return '-';
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
};

const statusLabel = computed(() => {
  const status = reservation.value?.ui_status || props.marker?.status;
  if (!status) return '-';

  const key = `CAPTAIN_RESERVATIONS.STATUS.${status.toUpperCase()}`;
  const translated = t(key);
  return translated === key
    ? reservation.value?.status_label || props.marker?.status_label || status
    : translated;
});

const statusColor = computed(() => {
  const status =
    reservation.value?.ui_status || props.marker?.status || 'draft';
  const colors = {
    draft: 'bg-n-slate-3 text-n-slate-11',
    pending_payment: 'bg-n-amber-3 text-n-amber-11',
    confirmed: 'bg-n-teal-3 text-n-teal-11',
    cancelled: 'bg-n-ruby-3 text-n-ruby-11',
  };
  return colors[status] || 'bg-n-slate-3 text-n-slate-11';
});

const onCopyPix = async () => {
  if (!pixValue.value) {
    useAlert(
      props.marker?.pix_reason === 'expired'
        ? t('CAPTAIN_RESERVATIONS.API.PIX_EXPIRED')
        : t('CAPTAIN_RESERVATIONS.API.PIX_NOT_GENERATED')
    );
    return;
  }

  try {
    await copyTextToClipboard(pixValue.value);
    useAlert(t('CAPTAIN_RESERVATIONS.API.PIX_COPIED'));
  } catch (error) {
    useAlert(t('CAPTAIN_RESERVATIONS.API.PIX_COPY_FAILED'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-2 text-sm">
    <p v-if="!hasMarker" class="text-n-slate-11">
      {{ $t('CAPTAIN_RESERVATIONS.SIDEBAR.NO_RESERVATION') }}
    </p>

    <div v-else-if="isLoading" class="text-n-slate-11">
      {{ $t('CAPTAIN_RESERVATIONS.SIDEBAR.LOADING') }}
    </div>

    <template v-else>
      <div class="flex items-start justify-between gap-2">
        <span class="text-n-slate-11">{{
          $t('CAPTAIN_RESERVATIONS.SIDEBAR.STATUS')
        }}</span>
        <span
          class="px-2 py-0.5 text-xs rounded font-medium"
          :class="statusColor"
        >
          {{ statusLabel }}
        </span>
      </div>
      <div class="flex items-start justify-between gap-2">
        <span class="text-n-slate-11">{{
          $t('CAPTAIN_RESERVATIONS.SIDEBAR.SUITE')
        }}</span>
        <span class="font-medium text-n-slate-12">{{
          reservation?.suite_identifier || marker?.suite || '-'
        }}</span>
      </div>
      <div class="flex items-start justify-between gap-2">
        <span class="text-n-slate-11">{{
          $t('CAPTAIN_RESERVATIONS.SIDEBAR.CHECK_IN')
        }}</span>
        <span class="font-medium text-n-slate-12">{{
          formatDateTime(reservation?.check_in_at || marker?.check_in_at)
        }}</span>
      </div>
      <div class="flex items-start justify-between gap-2">
        <span class="text-n-slate-11">{{
          $t('CAPTAIN_RESERVATIONS.SIDEBAR.CHECK_OUT')
        }}</span>
        <span class="font-medium text-n-slate-12">{{
          formatDateTime(reservation?.check_out_at || marker?.check_out_at)
        }}</span>
      </div>
      <div class="flex items-start justify-between gap-2">
        <span class="text-n-slate-11">{{
          $t('CAPTAIN_RESERVATIONS.SIDEBAR.AMOUNT')
        }}</span>
        <span class="font-medium text-n-slate-12">{{
          formatMoney(reservation?.amount || marker?.amount)
        }}</span>
      </div>
      <div class="flex items-start justify-between gap-2">
        <span class="text-n-slate-11">{{
          $t('CAPTAIN_RESERVATIONS.SIDEBAR.UPDATED_AT')
        }}</span>
        <span class="font-medium text-n-slate-12">{{
          formatDateTime(reservation?.updated_at || marker?.updated_at)
        }}</span>
      </div>

      <div class="pt-1">
        <Button
          size="xs"
          variant="outline"
          :label="$t('CAPTAIN_RESERVATIONS.ACTIONS.COPY_PIX')"
          @click="onCopyPix"
        />
      </div>
    </template>
  </div>
</template>
