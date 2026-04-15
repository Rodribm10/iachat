<script setup>
import { computed, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import MessageEditor from './MessageEditor.vue';
import { EVENTS, MESSAGE_TYPES, OFFSET_UNITS } from '../constants';

const props = defineProps({
  rule: { type: Object, default: null },
});
const emit = defineEmits(['close', 'saved']);
const { t } = useI18n();
const store = useStore();

const units = useMapGetter('captainUnits/getUnits');

const step = ref(0);
const form = ref({
  name: '',
  description: '',
  event: 'checkin.scheduled_at',
  offset_value: 10,
  offset_unit: 'minutes',
  offset_direction: 'before',
  enabled: true,
  unit_ids: [],
  categorias: '',
  permanencias: '',
  message_type: 'text',
  message_body: '',
  priority: 50,
});

watch(
  () => props.rule,
  r => {
    if (!r) return;
    const direction = (r.offset_minutes || 0) < 0 ? 'before' : 'after';
    const absMin = Math.abs(r.offset_minutes || 0);
    let unit = 'minutes';
    if (absMin % 1440 === 0 && absMin > 0) unit = 'days';
    else if (absMin % 60 === 0 && absMin > 0) unit = 'hours';
    const factor = OFFSET_UNITS.find(u => u.value === unit).factor;
    form.value = {
      name: r.name || '',
      description: r.description || '',
      event: r.event || 'checkin.scheduled_at',
      offset_value: absMin / factor || 10,
      offset_unit: unit,
      offset_direction: direction,
      enabled: r.enabled !== false,
      unit_ids: r.filters?.unit_ids || [],
      categorias: (r.filters?.categorias || []).join(', '),
      permanencias: (r.filters?.permanencias || []).join(', '),
      message_type: r.message_type || 'text',
      message_body: r.message_body || '',
      priority: r.priority || 50,
    };
  },
  { immediate: true }
);

const offsetMinutes = computed(() => {
  const factor = OFFSET_UNITS.find(
    u => u.value === form.value.offset_unit
  ).factor;
  const sign = form.value.offset_direction === 'before' ? -1 : 1;
  return sign * Number(form.value.offset_value) * factor;
});

const canNext = computed(() => {
  if (step.value === 0) return !!form.value.event && !!form.value.offset_value;
  if (step.value === 1) return form.value.unit_ids.length > 0;
  if (step.value === 2) return !!form.value.name && !!form.value.message_body;
  return true;
});

const next = () => {
  if (step.value < 3) step.value += 1;
};
const back = () => {
  if (step.value > 0) step.value -= 1;
};

const toList = str =>
  typeof str === 'string'
    ? str
        .split(',')
        .map(s => s.trim())
        .filter(Boolean)
    : str;

const save = async () => {
  const payload = {
    name: form.value.name,
    description: form.value.description,
    event: form.value.event,
    offset_minutes: offsetMinutes.value,
    enabled: form.value.enabled,
    filters: {
      unit_ids: form.value.unit_ids,
      categorias: toList(form.value.categorias),
      permanencias: toList(form.value.permanencias),
    },
    message_type: form.value.message_type,
    message_body: form.value.message_body,
    priority: Number(form.value.priority),
  };
  try {
    if (props.rule?.id) {
      await store.dispatch('captainLifecycleRules/update', {
        id: props.rule.id,
        ...payload,
      });
      useAlert(t('CAPTAIN_LIFECYCLE.RULES.TOAST.UPDATED'));
    } else {
      await store.dispatch('captainLifecycleRules/create', payload);
      useAlert(t('CAPTAIN_LIFECYCLE.RULES.TOAST.CREATED'));
    }
    emit('saved');
  } catch (e) {
    useAlert(e.message || 'Erro');
  }
};

const stepLabels = computed(() => [
  t('CAPTAIN_LIFECYCLE.RULES.WIZARD.STEP_LABELS.WHEN'),
  t('CAPTAIN_LIFECYCLE.RULES.WIZARD.STEP_LABELS.WHO'),
  t('CAPTAIN_LIFECYCLE.RULES.WIZARD.STEP_LABELS.WHAT'),
  t('CAPTAIN_LIFECYCLE.RULES.WIZARD.STEP_LABELS.REVIEW_TAB'),
]);
</script>

<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      @click.self="emit('close')"
    >
      <div
        class="bg-n-solid-1 rounded-xl p-6 w-[680px] max-h-[90vh] overflow-auto shadow-xl"
      >
        <h3 class="text-lg font-semibold mb-4">
          {{
            props.rule?.id
              ? t('CAPTAIN_LIFECYCLE.RULES.WIZARD.TITLE_EDIT')
              : t('CAPTAIN_LIFECYCLE.RULES.WIZARD.TITLE_CREATE')
          }}
        </h3>

        <ol class="flex gap-4 mb-6 text-xs">
          <li
            v-for="(label, idx) in stepLabels"
            :key="idx"
            :class="step === idx ? 'font-bold' : 'text-n-slate-11'"
          >
            {{ label }}
          </li>
        </ol>

        <!-- Step 0: When -->
        <div v-if="step === 0" class="space-y-3">
          <label class="block text-sm">
            {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.EVENT') }}
            <select
              v-model="form.event"
              class="w-full border rounded px-2 py-1"
            >
              <option v-for="e in EVENTS" :key="e.value" :value="e.value">
                {{ t(e.labelKey) }}
              </option>
            </select>
          </label>
          <div class="grid grid-cols-3 gap-3">
            <Input
              v-model="form.offset_value"
              type="number"
              :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.OFFSET_VALUE')"
            />
            <label class="block text-sm">
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.OFFSET_UNIT') }}
              <select
                v-model="form.offset_unit"
                class="w-full border rounded px-2 py-1"
              >
                <option
                  v-for="u in OFFSET_UNITS"
                  :key="u.value"
                  :value="u.value"
                >
                  {{
                    t(
                      `CAPTAIN_LIFECYCLE.RULES.WIZARD.OFFSET_UNITS.${u.value.toUpperCase()}`
                    )
                  }}
                </option>
              </select>
            </label>
            <label class="block text-sm">
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.OFFSET_DIRECTION') }}
              <select
                v-model="form.offset_direction"
                class="w-full border rounded px-2 py-1"
              >
                <option value="before">
                  {{
                    t('CAPTAIN_LIFECYCLE.RULES.WIZARD.OFFSET_DIRECTIONS.BEFORE')
                  }}
                </option>
                <option value="after">
                  {{
                    t('CAPTAIN_LIFECYCLE.RULES.WIZARD.OFFSET_DIRECTIONS.AFTER')
                  }}
                </option>
              </select>
            </label>
          </div>
        </div>

        <!-- Step 1: Who -->
        <div v-else-if="step === 1" class="space-y-3">
          <div>
            <div class="text-sm font-medium mb-2">
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.UNITS') }}
            </div>
            <div class="space-y-1">
              <label
                v-for="u in units"
                :key="u.id"
                class="flex items-center gap-2 text-sm"
              >
                <input v-model="form.unit_ids" type="checkbox" :value="u.id" />
                {{ u.name }}
              </label>
            </div>
          </div>
          <Input
            v-model="form.categorias"
            :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.CATEGORIAS')"
            placeholder="Alexa, Stilo"
          />
          <Input
            v-model="form.permanencias"
            :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.PERMANENCIAS')"
            placeholder="Pernoite, 2hrs"
          />
        </div>

        <!-- Step 2: What -->
        <div v-else-if="step === 2" class="space-y-3">
          <Input
            v-model="form.name"
            :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.NAME')"
          />
          <Input
            v-model="form.description"
            :label="t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.DESCRIPTION')"
          />
          <label class="block text-sm">
            {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.MESSAGE_TYPE') }}
            <select
              v-model="form.message_type"
              class="w-full border rounded px-2 py-1"
            >
              <option
                v-for="m in MESSAGE_TYPES"
                :key="m.value"
                :value="m.value"
              >
                {{ t(m.labelKey) }}
              </option>
            </select>
          </label>
          <div>
            <div class="text-sm mb-1">
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.MESSAGE_BODY') }}
            </div>
            <MessageEditor v-model="form.message_body" />
          </div>
          <label class="flex items-center gap-2 text-sm">
            <input v-model="form.enabled" type="checkbox" />
            {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.FIELDS.ENABLED') }}
          </label>
        </div>

        <!-- Step 3: Review -->
        <div v-else class="space-y-2 text-sm">
          <div>
            <strong>
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.REVIEW.NAME') }}
            </strong>
            {{ form.name }}
          </div>
          <div>
            <strong>
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.REVIEW.EVENT') }}
            </strong>
            {{ form.event }}
          </div>
          <div>
            <strong>
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.REVIEW.OFFSET') }}
            </strong>
            {{ offsetMinutes }}
          </div>
          <div>
            <strong>
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.REVIEW.UNITS') }}
            </strong>
            {{ form.unit_ids.join(', ') }}
          </div>
          <div>
            <strong>
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.REVIEW.MESSAGE') }}
            </strong>
          </div>
          <pre class="p-3 bg-n-alpha-2 rounded whitespace-pre-wrap">{{
            form.message_body
          }}</pre>
        </div>

        <div class="flex justify-between mt-6">
          <Button variant="outline" :disabled="step === 0" @click="back">
            {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.BACK') }}
          </Button>
          <div class="flex gap-2">
            <Button variant="outline" @click="emit('close')">
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.CANCEL') }}
            </Button>
            <Button v-if="step < 3" :disabled="!canNext" @click="next">
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.NEXT') }}
            </Button>
            <Button v-else @click="save">
              {{ t('CAPTAIN_LIFECYCLE.RULES.WIZARD.SAVE') }}
            </Button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
