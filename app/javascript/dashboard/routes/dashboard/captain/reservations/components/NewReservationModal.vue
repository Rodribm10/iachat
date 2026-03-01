<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  prefilledContactId: {
    type: [Number, String],
    default: '',
  },
  prefilledInboxId: {
    type: [Number, String],
    default: '',
  },
});

const emit = defineEmits(['close', 'success']);

const store = useStore();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

const dialogRef = ref(null);
const isLoading = ref(false);

onMounted(() => {
  dialogRef.value?.open();
});

const form = ref({
  contact_id: '',
  inbox_id: '',
  suite_identifier: '',
  check_in_at: '',
  check_out_at: '',
  total_amount: '',
});

watch(
  () => props.prefilledContactId,
  val => {
    if (val) form.value.contact_id = val;
  },
  { immediate: true }
);

watch(
  () => props.prefilledInboxId,
  val => {
    if (val) form.value.inbox_id = val;
  },
  { immediate: true }
);

const inboxOptions = computed(() => {
  return (inboxes.value || []).map(inbox => ({
    label: inbox.name,
    value: inbox.id,
  }));
});

const closeModal = () => {
  emit('close');
};

const submitReservation = async () => {
  const payload = { ...form.value };

  // Convert empty values to null or appropriate types if needed
  if (!payload.total_amount) payload.total_amount = 0;

  isLoading.value = true;
  try {
    await store.dispatch('captainReservations/create', payload);
    useAlert(t('CAPTAIN_RESERVATIONS.CREATE_SUCCESS'));
    emit('success');
    closeModal();
  } catch (error) {
    useAlert(error.message || t('CAPTAIN_RESERVATIONS.CREATE_ERROR'));
  } finally {
    isLoading.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="$t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.TITLE')"
    :confirm-button-label="
      $t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.CONFIRM')
    "
    :cancel-button-label="
      $t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.CANCEL')
    "
    :is-loading="isLoading"
    @confirm="submitReservation"
    @close="closeModal"
  >
    <div class="space-y-4">
      <!-- Contact ID -->
      <Input
        v-model="form.contact_id"
        type="number"
        :label="
          $t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.FIELDS.CONTACT_ID')
        "
        :placeholder="
          $t(
            'CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.FIELDS.CONTACT_ID_PLACEHOLDER'
          )
        "
        :disabled="!!props.prefilledContactId"
      />

      <!-- Inbox -->
      <div>
        <label class="block mb-1 text-sm font-medium text-n-slate-12">
          {{ $t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.FIELDS.INBOX') }}
        </label>
        <ComboBox
          v-model="form.inbox_id"
          :options="inboxOptions"
          :disabled="!!props.prefilledInboxId"
          :placeholder="
            $t(
              'CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.FIELDS.INBOX_PLACEHOLDER'
            )
          "
        />
      </div>

      <!-- Suite Identifier -->
      <Input
        v-model="form.suite_identifier"
        type="text"
        :label="
          $t(
            'CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.FIELDS.SUITE_IDENTIFIER'
          )
        "
      />

      <!-- Check In / Check Out -->
      <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
        <Input
          v-model="form.check_in_at"
          type="datetime-local"
          :label="
            $t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.FIELDS.CHECK_IN')
          "
        />
        <Input
          v-model="form.check_out_at"
          type="datetime-local"
          :label="
            $t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.FIELDS.CHECK_OUT')
          "
        />
      </div>

      <!-- Total Amount -->
      <Input
        v-model="form.total_amount"
        type="number"
        step="0.01"
        :label="
          $t('CAPTAIN_RESERVATIONS.NEW_RESERVATION_MODAL.FIELDS.TOTAL_AMOUNT')
        "
      />
    </div>
  </Dialog>
</template>
