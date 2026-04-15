<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import RuleWizardDialog from './components/RuleWizardDialog.vue';
import { RULE_TEMPLATES } from './constants';

const store = useStore();
const { t } = useI18n();

const rules = useMapGetter('captainLifecycleRules/getRecords');
const uiFlags = useMapGetter('captainLifecycleRules/getUIFlags');

const showWizard = ref(false);
const editing = ref(null);

onMounted(() => {
  store.dispatch('captainLifecycleRules/get');
  store.dispatch('captainUnits/get');
});

const openCreate = () => {
  editing.value = null;
  showWizard.value = true;
};
const openEdit = rule => {
  editing.value = rule;
  showWizard.value = true;
};
const openFromTemplate = tpl => {
  editing.value = {
    id: null,
    name: tpl.name,
    event: tpl.event,
    offset_minutes: tpl.offset_minutes,
    message_type: tpl.message_type,
    message_body: tpl.message_body,
    enabled: true,
    filters: {},
    priority: 50,
  };
  showWizard.value = true;
};
const onSaved = () => {
  showWizard.value = false;
  store.dispatch('captainLifecycleRules/get');
};
const toggle = async rule => {
  await store.dispatch('captainLifecycleRules/update', {
    id: rule.id,
    enabled: !rule.enabled,
  });
};
const remove = async rule => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CAPTAIN_LIFECYCLE.RULES.DELETE_CONFIRM'))) return;
  await store.dispatch('captainLifecycleRules/delete', rule.id);
  useAlert(t('CAPTAIN_LIFECYCLE.RULES.TOAST.DELETED'));
};

const isLoading = computed(() => uiFlags.value.fetchingList);

const formatOffset = offsetMinutes =>
  `${offsetMinutes >= 0 ? '+' : ''}${offsetMinutes}${t('CAPTAIN_LIFECYCLE.RULES.WIZARD.OFFSET_UNIT_LABEL')}`;
</script>

<template>
  <div class="p-6 space-y-6">
    <section>
      <h3 class="text-sm font-semibold mb-3 text-n-slate-11">
        {{ t('CAPTAIN_LIFECYCLE.RULES.TEMPLATES_TITLE') }}
      </h3>
      <div class="grid grid-cols-3 gap-3">
        <button
          v-for="tpl in RULE_TEMPLATES"
          :key="tpl.id"
          type="button"
          class="text-left p-3 border border-n-slate-4 rounded-lg hover:border-n-iris-9"
          @click="openFromTemplate(tpl)"
        >
          <div class="font-medium text-sm">{{ tpl.name }}</div>
          <div class="text-xs text-n-slate-11 mt-1">
            {{ tpl.event }} {{ formatOffset(tpl.offset_minutes) }}
          </div>
        </button>
      </div>
    </section>

    <section>
      <div class="flex justify-between items-center mb-3">
        <h3 class="text-base font-semibold">
          {{ t('CAPTAIN_LIFECYCLE.TABS.RULES') }}
        </h3>
        <Button @click="openCreate">
          {{ t('CAPTAIN_LIFECYCLE.RULES.CREATE') }}
        </Button>
      </div>

      <div v-if="isLoading"><Spinner /></div>
      <div
        v-else-if="rules.length === 0"
        class="text-center py-8 text-n-slate-11"
      >
        {{ t('CAPTAIN_LIFECYCLE.RULES.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm">
        <thead class="text-left text-n-slate-11">
          <tr>
            <th class="py-2">
              {{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.NAME') }}
            </th>
            <th>{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.EVENT') }}</th>
            <th>{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.OFFSET') }}</th>
            <th>{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.STATUS') }}</th>
            <th>{{ t('CAPTAIN_LIFECYCLE.RULES.COLUMNS.ACTIONS') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in rules" :key="r.id" class="border-t border-n-slate-4">
            <td class="py-2">{{ r.name }}</td>
            <td>{{ r.event }}</td>
            <td>{{ formatOffset(r.offset_minutes) }}</td>
            <td>
              {{
                r.enabled
                  ? t('CAPTAIN_LIFECYCLE.RULES.STATUS.ENABLED')
                  : t('CAPTAIN_LIFECYCLE.RULES.STATUS.DISABLED')
              }}
            </td>
            <td class="flex gap-2">
              <Button size="sm" variant="ghost" @click="openEdit(r)">
                {{ t('CAPTAIN_LIFECYCLE.RULES.ACTIONS.EDIT') }}
              </Button>
              <Button size="sm" variant="ghost" @click="toggle(r)">
                {{ t('CAPTAIN_LIFECYCLE.RULES.ACTIONS.TOGGLE') }}
              </Button>
              <Button size="sm" variant="ghost" @click="remove(r)">
                {{ t('CAPTAIN_LIFECYCLE.RULES.ACTIONS.DELETE') }}
              </Button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <RuleWizardDialog
      v-if="showWizard"
      :rule="editing"
      @close="showWizard = false"
      @saved="onSaved"
    />
  </div>
</template>
