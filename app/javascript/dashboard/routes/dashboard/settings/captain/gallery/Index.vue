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

const items = useMapGetter('captainGalleryItems/getItems');
const uiFlags = useMapGetter('captainGalleryItems/getUIFlags');

const deleteDialogRef = ref(null);
const itemToDelete = ref(null);

const hasItems = computed(() => items.value && items.value.length > 0);

onMounted(async () => {
  await store.dispatch('captainGalleryItems/get');
});

const goToNew = () => {
  router.push({
    name: 'captain_settings_gallery_edit',
    params: { id: 'new' },
  });
};

const goToEdit = item => {
  router.push({
    name: 'captain_settings_gallery_edit',
    params: { id: item.id },
  });
};

const openDeleteDialog = item => {
  itemToDelete.value = item;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  if (!itemToDelete.value) return;
  try {
    await store.dispatch('captainGalleryItems/delete', itemToDelete.value.id);
    useAlert(t('CAPTAIN_SETTINGS.GALLERY.DELETE.API.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('CAPTAIN_SETTINGS.GALLERY.DELETE.API.ERROR_MESSAGE'));
  } finally {
    itemToDelete.value = null;
  }
};
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="t('CAPTAIN_SETTINGS.GALLERY.TITLE')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('CAPTAIN_SETTINGS.GALLERY.TITLE')"
        :description="t('CAPTAIN_SETTINGS.GALLERY.DESC')"
      >
        <template #actions>
          <Button
            :label="t('CAPTAIN_SETTINGS.GALLERY.ADD_ITEM')"
            icon="i-lucide-plus"
            @click="goToNew"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <div class="flex flex-col px-6 pb-8">
        <div v-if="hasItems" class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-n-weak">
                <th
                  class="py-3 pr-4 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.GALLERY.LIST.TABLE_HEADER[0]') }}
                </th>
                <th
                  class="py-3 pr-4 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.GALLERY.LIST.TABLE_HEADER[1]') }}
                </th>
                <th
                  class="py-3 pr-4 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.GALLERY.LIST.TABLE_HEADER[2]') }}
                </th>
                <th
                  class="py-3 pr-4 text-left text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.GALLERY.LIST.TABLE_HEADER[3]') }}
                </th>
                <th
                  class="py-3 text-right text-xs font-medium uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('CAPTAIN_SETTINGS.GALLERY.LIST.TABLE_HEADER[4]') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr v-for="item in items" :key="item.id">
                <td class="py-4 pr-4">
                  <img
                    v-if="item.image_url"
                    :src="item.image_url"
                    :alt="item.description"
                    class="h-16 w-24 rounded object-cover"
                  />
                </td>
                <td class="py-4 pr-4">
                  <p class="mb-0 font-medium text-n-slate-12">
                    {{
                      item.scope === 'global'
                        ? t('CAPTAIN_SETTINGS.GALLERY.FORM.INBOX.GLOBAL_OPTION')
                        : item.inbox_name || '-'
                    }}
                  </p>
                  <p class="mb-0 text-xs text-n-slate-10">
                    {{ item.description }}
                  </p>
                </td>
                <td class="py-4 pr-4 text-n-slate-11">
                  {{ item.suite_category }}
                </td>
                <td class="py-4 pr-4 text-n-slate-11">
                  {{ item.suite_number }}
                </td>
                <td class="py-4">
                  <div class="flex justify-end gap-2">
                    <Button
                      icon="i-lucide-pencil"
                      variant="ghost"
                      size="sm"
                      :label="t('CAPTAIN_SETTINGS.GALLERY.EDIT_ITEM')"
                      @click="goToEdit(item)"
                    />
                    <Button
                      icon="i-lucide-trash-2"
                      variant="ghost"
                      size="sm"
                      color="ruby"
                      :label="t('CAPTAIN_SETTINGS.GALLERY.DELETE_ITEM')"
                      @click="openDeleteDialog(item)"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-else
          class="flex flex-col items-center justify-center gap-4 py-20 text-center"
        >
          <div class="size-16 rounded-full bg-n-blue-2" />
          <div class="flex flex-col gap-1">
            <p class="mb-0 text-base font-medium text-n-slate-12">
              {{ t('CAPTAIN_SETTINGS.GALLERY.LIST.ADD_NEW_ITEM') }}
            </p>
            <p class="mb-0 max-w-sm text-sm text-n-slate-10">
              {{ t('CAPTAIN_SETTINGS.GALLERY.LIST.NO_ITEMS_MESSAGE') }}
            </p>
          </div>
          <Button
            :label="t('CAPTAIN_SETTINGS.GALLERY.ADD_ITEM')"
            icon="i-lucide-plus"
            @click="goToNew"
          />
        </div>
      </div>

      <Dialog
        ref="deleteDialogRef"
        type="alert"
        :title="t('CAPTAIN_SETTINGS.GALLERY.DELETE.CONFIRM.TITLE')"
        :description="t('CAPTAIN_SETTINGS.GALLERY.DELETE.CONFIRM.MESSAGE')"
        :confirm-button-label="t('CAPTAIN_SETTINGS.GALLERY.DELETE.CONFIRM.YES')"
        @confirm="confirmDelete"
      />
    </template>
  </SettingsLayout>
</template>
