<script setup>
import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainUnitsAPI from 'dashboard/api/captain/units';

const props = defineProps({
  unit: { type: Object, required: true },
});

const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getWhatsAppInboxes');

const expanded = ref(false);
const conciergeInboxId = ref(props.unit.concierge_inbox_id || null);
const personaName = ref(props.unit.concierge_config?.persona_name || 'Sofia');
const knowledge = ref(props.unit.concierge_config?.knowledge || '');
const variables = ref(
  Object.entries(props.unit.concierge_config?.variables || {}).map(
    ([k, v]) => ({
      k,
      v,
    })
  )
);

const addVariable = () => variables.value.push({ k: '', v: '' });
const removeVariable = i => variables.value.splice(i, 1);

const save = async () => {
  try {
    const varsObj = Object.fromEntries(
      variables.value.filter(x => x.k).map(x => [x.k, x.v])
    );
    await CaptainUnitsAPI.updateConcierge(props.unit.id, {
      concierge_inbox_id: conciergeInboxId.value,
      concierge_config: {
        persona_name: personaName.value,
        knowledge: knowledge.value,
        variables: varsObj,
      },
    });
    useAlert(t('CAPTAIN_LIFECYCLE.SETTINGS.TOAST.CONCIERGE_SAVED'));
  } catch (e) {
    useAlert(e.message || 'Error saving concierge');
  }
};
</script>

<template>
  <div class="border border-n-slate-4 rounded-lg p-4">
    <div
      class="flex justify-between items-center cursor-pointer"
      @click="expanded = !expanded"
    >
      <div>
        <div class="font-medium">{{ unit.name }}</div>
        <div class="text-xs text-n-slate-11">
          {{
            unit.concierge_inbox_id
              ? t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_CONFIGURED')
              : t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_NOT_CONFIGURED')
          }}
        </div>
      </div>
      <span>{{ expanded ? '▾' : '▸' }}</span>
    </div>

    <div v-if="expanded" class="mt-4 space-y-3">
      <label class="block text-sm">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_INBOX') }}
        <select
          v-model="conciergeInboxId"
          class="w-full border rounded px-2 py-1"
        >
          <option :value="null">—</option>
          <option v-for="ib in inboxes" :key="ib.id" :value="ib.id">
            {{ ib.name }}
          </option>
        </select>
      </label>

      <Input
        v-model="personaName"
        :label="t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_PERSONA')"
      />

      <label class="block text-sm">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_KNOWLEDGE') }}
        <textarea
          v-model="knowledge"
          rows="8"
          class="w-full border rounded p-2 font-mono text-xs"
        />
      </label>

      <div>
        <div class="text-sm font-medium mb-2">
          {{ t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_VARIABLES') }}
        </div>
        <div
          v-for="(variable, i) in variables"
          :key="i"
          class="flex gap-2 mb-2"
        >
          <input
            v-model="variable.k"
            :placeholder="
              t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_VARIABLE_KEY')
            "
            class="border rounded px-2 py-1 w-1/3"
          />
          <input
            v-model="variable.v"
            :placeholder="
              t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_VARIABLE_VALUE')
            "
            class="border rounded px-2 py-1 flex-1"
          />
          <Button
            variant="ghost"
            size="sm"
            icon="i-lucide-x"
            @click="removeVariable(i)"
          />
        </div>
        <Button
          variant="outline"
          size="sm"
          icon="i-lucide-plus"
          :label="t('CAPTAIN_LIFECYCLE.SETTINGS.CONCIERGE_ADD_VARIABLE')"
          @click="addVariable"
        />
      </div>

      <Button @click="save">
        {{ t('CAPTAIN_LIFECYCLE.SETTINGS.SAVE') }}
      </Button>
    </div>
  </div>
</template>
