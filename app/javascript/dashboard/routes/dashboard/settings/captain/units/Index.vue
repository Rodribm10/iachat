<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import SettingsLayout from '../../SettingsLayout.vue';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { t } = useI18n();
const router = useRouter();
const store = useStore();

const units = useMapGetter('captainUnits/getUnits');
const uiFlags = useMapGetter('captainUnits/getUIFlags');

const deleteDialogRef = ref(null);
const unitToDelete = ref(null);

const hasUnits = computed(() => units.value && units.value.length > 0);

onMounted(async () => {
  await store.dispatch('captainUnits/get');
});

const goToNew = () => {
  router.push({
    name: 'captain_settings_units_edit',
    params: { id: 'new' },
  });
};

const goToEdit = unit => {
  router.push({
    name: 'captain_settings_units_edit',
    params: { id: unit.id },
  });
};

const openDeleteDialog = unit => {
  unitToDelete.value = unit;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  if (!unitToDelete.value) return;
  try {
    await store.dispatch('captainUnits/delete', unitToDelete.value.id);
    useAlert(t('CAPTAIN_SETTINGS.UNITS.DELETE.API.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.UNITS.DELETE.API.ERROR_MESSAGE'));
  } finally {
    unitToDelete.value = null;
  }
};
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('CAPTAIN_SETTINGS.UNITS.TITLE')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CAPTAIN_SETTINGS.UNITS.TITLE')"
        :description="t('CAPTAIN_SETTINGS.UNITS.DESC')"
      >
        <template #actions>
          <Button
            :label="t('CAPTAIN_SETTINGS.UNITS.ADD_UNIT')"
            icon="i-lucide-plus"
            @click="goToNew"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="flex flex-col px-6 pb-8">
        <!-- Tabela de Unidades -->
        <div v-if="hasUnits" class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-n-weak">
                <th
                  class="py-3 pr-4 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.UNITS.LIST.TABLE_HEADER[0]') }}
                </th>
                <th
                  class="py-3 pr-4 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.UNITS.LIST.TABLE_HEADER[1]') }}
                </th>
                <th
                  class="py-3 pr-4 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.UNITS.LIST.TABLE_HEADER[2]') }}
                </th>
                <th
                  class="py-3 pr-4 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.UNITS.LIST.TABLE_HEADER[3]') }}
                </th>
                <th
                  class="py-3 text-right text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.UNITS.LIST.TABLE_HEADER[4]') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr v-for="unit in units" :key="unit.id">
                <td class="py-4 pr-4">
                  <p class="mb-0 font-medium text-n-slate-12">
                    {{ unit.name }}
                  </p>
                  <p class="mb-0 text-xs text-n-slate-10">
                    {{ unit.inter_pix_key }}
                  </p>
                </td>
                <td class="py-4 pr-4 text-n-slate-11">
                  <p class="mb-0 text-n-slate-11">
                    {{ unit.inter_account_number }}
                  </p>
                  <p class="mb-0 text-xs text-n-slate-10">
                    {{
                      unit.inbox_name ||
                      t('CAPTAIN_SETTINGS.UNITS.INBOX.NO_UNIT')
                    }}
                  </p>
                </td>
                <td class="py-4 pr-4">
                  <div class="flex gap-2">
                    <span
                      v-if="unit.has_cert"
                      class="inline-flex items-center gap-1 rounded-full bg-n-teal-2 px-2 py-0.5 text-xs font-medium text-n-teal-11"
                    >
                      {{ t('CAPTAIN_SETTINGS.UNITS.LIST.CERT') }}
                    </span>
                    <span
                      v-else
                      class="inline-flex items-center gap-1 rounded-full bg-n-amber-2 px-2 py-0.5 text-xs font-medium text-n-amber-11"
                    >
                      {{ t('CAPTAIN_SETTINGS.UNITS.LIST.CERT') }}
                    </span>
                    <span
                      v-if="unit.has_key"
                      class="inline-flex items-center gap-1 rounded-full bg-n-teal-2 px-2 py-0.5 text-xs font-medium text-n-teal-11"
                    >
                      {{ t('CAPTAIN_SETTINGS.UNITS.LIST.KEY') }}
                    </span>
                    <span
                      v-else
                      class="inline-flex items-center gap-1 rounded-full bg-n-amber-2 px-2 py-0.5 text-xs font-medium text-n-amber-11"
                    >
                      {{ t('CAPTAIN_SETTINGS.UNITS.LIST.KEY') }}
                    </span>
                  </div>
                </td>
                <td class="py-4 pr-4">
                  <span
                    v-if="unit.proactive_pix_polling_enabled"
                    class="inline-flex items-center gap-1 rounded-full bg-n-teal-2 px-2 py-0.5 text-xs font-medium text-n-teal-11"
                  >
                    {{ t('CAPTAIN_SETTINGS.UNITS.LIST.PROACTIVE_ON') }}
                  </span>
                  <span
                    v-else
                    class="inline-flex items-center gap-1 rounded-full bg-n-slate-3 px-2 py-0.5 text-xs font-medium text-n-slate-11"
                  >
                    {{ t('CAPTAIN_SETTINGS.UNITS.LIST.PROACTIVE_OFF') }}
                  </span>
                </td>
                <td class="py-4">
                  <div class="flex justify-end gap-2">
                    <Button
                      icon="i-lucide-pencil"
                      variant="ghost"
                      size="sm"
                      :label="t('CAPTAIN_SETTINGS.UNITS.EDIT_UNIT')"
                      @click="goToEdit(unit)"
                    />
                    <Button
                      icon="i-lucide-trash-2"
                      variant="ghost"
                      size="sm"
                      color="ruby"
                      :label="t('CAPTAIN_SETTINGS.UNITS.DELETE_UNIT')"
                      @click="openDeleteDialog(unit)"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Empty State -->
        <div
          v-else
          class="flex flex-col items-center justify-center gap-4 py-20 text-center"
        >
          <div class="size-16 rounded-full bg-n-blue-2" />
          <div class="flex flex-col gap-1">
            <p class="mb-0 text-base font-medium text-n-slate-12">
              {{ t('CAPTAIN_SETTINGS.UNITS.LIST.ADD_NEW_UNIT') }}
            </p>
            <p class="mb-0 max-w-sm text-sm text-n-slate-10">
              {{ t('CAPTAIN_SETTINGS.UNITS.LIST.NO_UNITS_MESSAGE') }}
            </p>
          </div>
          <Button
            :label="t('CAPTAIN_SETTINGS.UNITS.ADD_UNIT')"
            icon="i-lucide-plus"
            @click="goToNew"
          />
        </div>
      </div>

      <!-- Dialog de Confirmação de Exclusão -->
      <Dialog
        ref="deleteDialogRef"
        type="alert"
        :title="t('CAPTAIN_SETTINGS.UNITS.DELETE.CONFIRM.TITLE')"
        :description="t('CAPTAIN_SETTINGS.UNITS.DELETE.CONFIRM.MESSAGE')"
        :confirm-button-label="t('CAPTAIN_SETTINGS.UNITS.DELETE.CONFIRM.YES')"
        @confirm="confirmDelete"
      />
    </template>
  </SettingsLayout>
</template>
