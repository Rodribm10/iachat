<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DeliveryPreviewModal from './components/DeliveryPreviewModal.vue';

const store = useStore();
const { t } = useI18n();

const deliveries = useMapGetter('captainLifecycleDeliveries/getRecords');
const meta = useMapGetter('captainLifecycleDeliveries/getMeta');
const uiFlags = useMapGetter('captainLifecycleDeliveries/getUIFlags');

const status = ref('');
const page = ref(1);
const selectedDelivery = ref(null);

const STATUS_OPTIONS = [
  { value: '', key: 'ALL' },
  { value: 'scheduled', key: 'SCHEDULED' },
  { value: 'sent', key: 'SENT' },
  { value: 'skipped', key: 'SKIPPED' },
  { value: 'failed', key: 'FAILED' },
  { value: 'cancelled', key: 'CANCELLED' },
];

const fetchDeliveries = () => {
  store.dispatch('captainLifecycleDeliveries/get', {
    page: page.value,
    ...(status.value ? { status: status.value } : {}),
  });
};

onMounted(fetchDeliveries);
watch([status, page], fetchDeliveries);

const isLoading = computed(() => uiFlags.value.fetchingList);
const totalCount = computed(() => meta.value.total_count || 0);
</script>

<template>
  <div class="p-6">
    <div class="flex items-center gap-4 mb-4">
      <label class="flex items-center gap-2 text-sm">
        {{ t('CAPTAIN_LIFECYCLE.HISTORY.FILTERS.STATUS') }}:
        <select v-model="status" class="border rounded px-2 py-1">
          <option
            v-for="opt in STATUS_OPTIONS"
            :key="opt.value"
            :value="opt.value"
          >
            {{
              opt.value
                ? t(`CAPTAIN_LIFECYCLE.HISTORY.STATUS.${opt.key}`)
                : t('CAPTAIN_LIFECYCLE.HISTORY.FILTERS.ALL')
            }}
          </option>
        </select>
      </label>
      <span class="text-sm text-n-slate-11">
        {{ totalCount }} {{ t('CAPTAIN_LIFECYCLE.HISTORY.TOTAL') }}
      </span>
    </div>

    <div v-if="isLoading" class="flex justify-center py-8">
      <Spinner />
    </div>

    <div
      v-else-if="deliveries.length === 0"
      class="text-center py-8 text-n-slate-11"
    >
      {{ t('CAPTAIN_LIFECYCLE.HISTORY.EMPTY') }}
    </div>

    <table v-else class="w-full text-sm">
      <thead class="text-left text-n-slate-11">
        <tr>
          <th class="py-2">
            {{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.RULE') }}
          </th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.CUSTOMER') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.RESERVATION') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.STATUS') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.FIRE_AT') }}</th>
          <th>{{ t('CAPTAIN_LIFECYCLE.HISTORY.COLUMNS.REASON') }}</th>
          <th />
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="d in deliveries"
          :key="d.id"
          class="border-t border-n-slate-4"
        >
          <td class="py-2">{{ d.lifecycle_rule_name || '—' }}</td>
          <td>{{ d.reservation?.customer_name || '—' }}</td>
          <td>
            {{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.RESERVATION_ID')
            }}{{ d.captain_reservation_id }}
          </td>
          <td>
            {{
              t(`CAPTAIN_LIFECYCLE.HISTORY.STATUS.${d.status.toUpperCase()}`)
            }}
          </td>
          <td>{{ new Date(d.fire_at).toLocaleString('pt-BR') }}</td>
          <td>{{ d.skip_reason || d.failure_reason || '' }}</td>
          <td>
            <Button size="sm" variant="ghost" @click="selectedDelivery = d">
              {{ t('CAPTAIN_LIFECYCLE.HISTORY.PREVIEW') }}
            </Button>
          </td>
        </tr>
      </tbody>
    </table>

    <div class="flex justify-center gap-2 mt-4">
      <Button :disabled="page <= 1" @click="page -= 1">
        {{ t('CAPTAIN_LIFECYCLE.HISTORY.PAGINATION.PREV') }}
      </Button>
      <span class="text-sm self-center">{{ page }}</span>
      <Button :disabled="deliveries.length < 25" @click="page += 1">
        {{ t('CAPTAIN_LIFECYCLE.HISTORY.PAGINATION.NEXT') }}
      </Button>
    </div>

    <DeliveryPreviewModal
      :delivery="selectedDelivery"
      @close="selectedDelivery = null"
    />
  </div>
</template>
