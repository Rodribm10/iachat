<script setup>
import { onMounted, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConciergeUnitCard from './components/ConciergeUnitCard.vue';

const store = useStore();
const { t } = useI18n();

const config = useMapGetter('captainLifecycleConfig/getConfig');
const uiFlags = useMapGetter('captainLifecycleConfig/getUIFlags');
const units = useMapGetter('captainUnits/getUnits');
const labels = useMapGetter('labels/getLabels');

const form = ref({});

const syncForm = () => {
  form.value = { ...config.value };
};

watch(config, syncForm, { immediate: true });

onMounted(() => {
  store.dispatch('captainLifecycleConfig/fetch');
  store.dispatch('captainUnits/get');
  store.dispatch('labels/get');
});

const save = async () => {
  try {
    await store.dispatch('captainLifecycleConfig/update', {
      quiet_hours_enabled: form.value.quiet_hours_enabled,
      quiet_hours_from: form.value.quiet_hours_from,
      quiet_hours_to: form.value.quiet_hours_to,
      min_interval_minutes: Number(form.value.min_interval_minutes),
      pause_on_customer_reply: form.value.pause_on_customer_reply,
      pause_on_customer_reply_within_minutes: Number(
        form.value.pause_on_customer_reply_within_minutes
      ),
      opt_out_label_id: form.value.opt_out_label_id || null,
    });
    useAlert(t('CAPTAIN_LIFECYCLE.SETTINGS.TOAST.SAVED'));
  } catch (e) {
    useAlert(e.message || 'Error');
  }
};
</script>

<template>
  <div class="p-6 space-y-8">
    <section>
      <h3 class="text-base font-semibold mb-3">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.GUARDS_TITLE') }}
      </h3>
      <div v-if="uiFlags.fetching">
        <Spinner />
      </div>
      <div v-else class="space-y-3 max-w-xl">
        <label class="flex items-center gap-2 cursor-pointer">
          <Checkbox v-model="form.quiet_hours_enabled" />
          <span class="text-sm">
            {{ t('CAPTAIN_LIFECYCLE.SETTINGS.QUIET_HOURS_ENABLED') }}
          </span>
        </label>

        <div v-if="form.quiet_hours_enabled" class="flex gap-3">
          <label class="flex-1 text-sm">
            {{ t('CAPTAIN_LIFECYCLE.SETTINGS.QUIET_HOURS_FROM') }}
            <input
              v-model="form.quiet_hours_from"
              type="time"
              class="w-full border rounded px-2 py-1"
            />
          </label>
          <label class="flex-1 text-sm">
            {{ t('CAPTAIN_LIFECYCLE.SETTINGS.QUIET_HOURS_TO') }}
            <input
              v-model="form.quiet_hours_to"
              type="time"
              class="w-full border rounded px-2 py-1"
            />
          </label>
        </div>

        <Input
          v-model="form.min_interval_minutes"
          type="number"
          :label="t('CAPTAIN_LIFECYCLE.SETTINGS.MIN_INTERVAL')"
          :message="t('CAPTAIN_LIFECYCLE.SETTINGS.MIN_INTERVAL_HELP')"
        />

        <label class="flex items-center gap-2 cursor-pointer">
          <Checkbox v-model="form.pause_on_customer_reply" />
          <span class="text-sm">
            {{ t('CAPTAIN_LIFECYCLE.SETTINGS.PAUSE_ON_REPLY') }}
          </span>
        </label>

        <Input
          v-if="form.pause_on_customer_reply"
          v-model="form.pause_on_customer_reply_within_minutes"
          type="number"
          :label="t('CAPTAIN_LIFECYCLE.SETTINGS.PAUSE_ON_REPLY_WINDOW')"
        />

        <label class="block text-sm">
          {{ t('CAPTAIN_LIFECYCLE.SETTINGS.OPT_OUT_LABEL') }}
          <select
            v-model="form.opt_out_label_id"
            class="w-full border rounded px-2 py-1"
          >
            <option :value="null">—</option>
            <option v-for="label in labels" :key="label.id" :value="label.id">
              {{ label.title }}
            </option>
          </select>
        </label>

        <p class="text-xs text-n-slate-11">
          {{ t('CAPTAIN_LIFECYCLE.SETTINGS.MAX_PER_RESERVATION_INFO') }}
        </p>

        <Button :disabled="uiFlags.updating" @click="save">
          {{ t('CAPTAIN_LIFECYCLE.SETTINGS.SAVE') }}
        </Button>
      </div>
    </section>

    <section>
      <h3 class="text-base font-semibold mb-3">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_TITLE') }}
      </h3>
      <div class="space-y-3">
        <ConciergeUnitCard v-for="u in units" :key="u.id" :unit="u" />
      </div>
    </section>
  </div>
</template>
