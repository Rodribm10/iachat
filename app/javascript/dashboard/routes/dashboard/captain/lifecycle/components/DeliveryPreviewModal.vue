<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  delivery: { type: Object, default: null },
});
const emit = defineEmits(['close']);
const { t } = useI18n();
</script>

<template>
  <Teleport to="body">
    <div
      v-if="delivery"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      @click.self="emit('close')"
    >
      <div
        class="bg-n-solid-1 rounded-xl p-6 w-[560px] max-h-[80vh] overflow-auto shadow-xl"
      >
        <h3 class="text-lg font-semibold mb-4">
          {{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.TITLE') }}
        </h3>
        <div class="space-y-3 text-sm">
          <div>
            <strong>{{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.RULE') }}:</strong>
            {{ delivery.lifecycle_rule_name || '—' }}
          </div>
          <div>
            <strong>{{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.STATUS') }}:</strong>
            {{ delivery.status }}
          </div>
          <div v-if="delivery.skip_reason">
            <strong>{{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.REASON') }}:</strong>
            {{ delivery.skip_reason }}
          </div>
          <div v-if="delivery.failure_reason">
            <strong>{{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.ERROR') }}:</strong>
            {{ delivery.failure_reason }}
          </div>
          <div>
            <strong>{{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.FIRE_AT') }}:</strong>
            {{ delivery.fire_at }}
          </div>
          <div v-if="delivery.sent_at">
            <strong>{{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.SENT_AT') }}:</strong>
            {{ delivery.sent_at }}
          </div>
          <div>
            <strong
              >{{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.RENDERED') }}:</strong
            >
            <pre class="mt-1 p-3 bg-n-alpha-2 rounded whitespace-pre-wrap">{{
              delivery.rendered_body || '—'
            }}</pre>
          </div>
        </div>
        <div class="flex justify-end mt-6">
          <Button variant="outline" @click="emit('close')">
            {{ t('CAPTAIN_LIFECYCLE.HISTORY.MODAL.CLOSE') }}
          </Button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
