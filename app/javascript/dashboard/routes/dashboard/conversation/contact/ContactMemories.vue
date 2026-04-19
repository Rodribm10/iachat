<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNow } from 'date-fns';
import ContactMemoriesAPI from 'dashboard/api/captain/contactMemories';

import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
});

const { t } = useI18n();

const memories = ref([]);
const loading = ref(true);
const error = ref(null);

// Tailwind classes for the colored chip per memory type. Kept close to the
// color language already used by the Chatwoot sidebar (n-* tokens for slate
// and Radix-like accents for the accent colors).
const TYPE_STYLES = {
  preferencia: 'bg-n-blue-9/10 text-n-blue-11',
  contexto_pessoal: 'bg-n-blue-9/10 text-n-blue-11',
  data_comemorativa: 'bg-n-iris-9/10 text-n-iris-11',
  vinculo_social: 'bg-n-teal-9/10 text-n-teal-11',
  vinculo_comercial: 'bg-n-teal-9/10 text-n-teal-11',
  feedback_positivo: 'bg-n-teal-9/10 text-n-teal-11',
  padrao_comportamental: 'bg-n-slate-9/10 text-n-slate-11',
  reclamacao: 'bg-n-ruby-9/10 text-n-ruby-11',
  restricao: 'bg-n-amber-9/10 text-n-amber-11',
};

const DEFAULT_TYPE_STYLE = 'bg-n-slate-9/10 text-n-slate-11';

const typeBadgeClasses = memoryType =>
  TYPE_STYLES[memoryType] || DEFAULT_TYPE_STYLE;

const typeLabel = memoryType => {
  const key = `CONVERSATION_SIDEBAR.CONTACT_MEMORIES.TYPE_LABELS.${memoryType}`;
  const translated = t(key);
  // Fallback to the raw type when the translation key does not exist so we
  // never render an empty chip.
  return translated === key ? memoryType : translated;
};

const confidenceBarClass = confidence => {
  if (confidence >= 0.9) return 'bg-n-teal-9';
  if (confidence >= 0.7) return 'bg-n-amber-9';
  return 'bg-n-slate-7';
};

const relativeTime = isoString => {
  if (!isoString) return '';
  try {
    return formatDistanceToNow(new Date(isoString), { addSuffix: true });
  } catch (_e) {
    return '';
  }
};

const hasMemories = computed(() => memories.value.length > 0);

async function load() {
  if (!props.contactId) return;
  loading.value = true;
  error.value = null;
  try {
    const { data } = await ContactMemoriesAPI.list(props.contactId);
    memories.value = data.data || [];
  } catch (e) {
    error.value =
      e?.message || t('CONVERSATION_SIDEBAR.CONTACT_MEMORIES.ERROR_LOADING');
  } finally {
    loading.value = false;
  }
}

async function deleteMemory(id) {
  const confirmed =
    // eslint-disable-next-line no-alert
    window.confirm(t('CONVERSATION_SIDEBAR.CONTACT_MEMORIES.CONFIRM_DELETE'));
  if (!confirmed) return;
  await ContactMemoriesAPI.destroy(props.contactId, id);
  await load();
}

async function forgetAll() {
  const confirmed =
    // eslint-disable-next-line no-alert
    window.confirm(
      t('CONVERSATION_SIDEBAR.CONTACT_MEMORIES.CONFIRM_FORGET_ALL')
    );
  if (!confirmed) return;
  await ContactMemoriesAPI.forgetAll(props.contactId);
  await load();
}

onMounted(load);

watch(
  () => props.contactId,
  newId => {
    if (newId) load();
  }
);
</script>

<template>
  <div class="flex flex-col gap-3 px-4 pt-2 pb-4">
    <!-- Loading skeleton -->
    <div
      v-if="loading"
      class="flex items-center justify-center py-6 text-n-slate-11"
    >
      <Spinner />
    </div>

    <!-- Error -->
    <div
      v-else-if="error"
      class="flex items-start gap-2 rounded-md bg-n-ruby-9/10 px-3 py-2 text-sm text-n-ruby-11"
    >
      <Icon icon="i-lucide-alert-triangle" class="mt-0.5 flex-shrink-0" />
      <span>{{ error }}</span>
    </div>

    <!-- Empty state -->
    <div
      v-else-if="!hasMemories"
      class="flex flex-col items-center gap-2 py-8 text-center"
    >
      <div
        class="flex h-12 w-12 items-center justify-center rounded-full bg-n-alpha-2 text-n-slate-10"
      >
        <Icon icon="i-lucide-brain" class="text-xl" />
      </div>
      <p class="text-sm font-medium text-n-slate-12">
        {{ t('CONVERSATION_SIDEBAR.CONTACT_MEMORIES.EMPTY_TITLE') }}
      </p>
      <p class="max-w-[240px] text-xs leading-5 text-n-slate-11">
        {{ t('CONVERSATION_SIDEBAR.CONTACT_MEMORIES.EMPTY_HINT') }}
      </p>
    </div>

    <!-- Memory list -->
    <template v-else>
      <ul class="flex flex-col gap-2">
        <li
          v-for="memory in memories"
          :key="memory.id"
          class="group/memory flex flex-col gap-2 rounded-lg border border-n-strong bg-n-solid-1 p-3 transition-colors hover:border-n-slate-7"
        >
          <div class="flex items-start justify-between gap-2">
            <span
              class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
              :class="typeBadgeClasses(memory.memory_type)"
            >
              {{ typeLabel(memory.memory_type) }}
            </span>
            <NextButton
              variant="ghost"
              color="ruby"
              size="xs"
              icon="i-lucide-trash-2"
              class="opacity-0 group-hover/memory:opacity-100 focus-visible:opacity-100"
              :aria-label="t('CONVERSATION_SIDEBAR.CONTACT_MEMORIES.FORGET')"
              @click="deleteMemory(memory.id)"
            />
          </div>

          <p
            class="m-0 text-sm leading-relaxed text-n-slate-12 whitespace-pre-line break-words"
          >
            {{ memory.content }}
          </p>

          <div
            class="flex items-center justify-between gap-3 pt-1 text-xs text-n-slate-11"
          >
            <div
              class="flex items-center gap-1.5 min-w-0"
              :title="`${t('CONVERSATION_SIDEBAR.CONTACT_MEMORIES.CONFIDENCE')}: ${Math.round(memory.confidence * 100)}%`"
            >
              <span
                class="relative h-1.5 w-12 overflow-hidden rounded-full bg-n-alpha-2"
              >
                <span
                  class="absolute left-0 top-0 h-full rounded-full"
                  :class="confidenceBarClass(memory.confidence)"
                  :style="{ width: `${Math.round(memory.confidence * 100)}%` }"
                />
              </span>
              <span class="tabular-nums">
                {{ `${Math.round(memory.confidence * 100)}%` }}
              </span>
            </div>
            <span class="truncate">{{ relativeTime(memory.created_at) }}</span>
          </div>
        </li>
      </ul>

      <div class="flex justify-end pt-1">
        <NextButton
          variant="ghost"
          color="ruby"
          size="xs"
          icon="i-lucide-trash-2"
          :label="t('CONVERSATION_SIDEBAR.CONTACT_MEMORIES.FORGET_ALL')"
          @click="forgetAll"
        />
      </div>
    </template>
  </div>
</template>
