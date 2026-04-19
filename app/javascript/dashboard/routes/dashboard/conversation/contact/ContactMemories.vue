<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactMemoriesAPI from 'dashboard/api/captain/contactMemories';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
});
const { t } = useI18n();
const memories = ref([]);
const loading = ref(true);
const error = ref(null);

async function load() {
  loading.value = true;
  error.value = null;
  try {
    const { data } = await ContactMemoriesAPI.list(props.contactId);
    memories.value = data.data;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}

async function deleteMemory(id) {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CAPTAIN.MEMORY.CONFIRM_DELETE'))) return;
  await ContactMemoriesAPI.destroy(props.contactId, id);
  await load();
}

async function forgetAll() {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CAPTAIN.MEMORY.CONFIRM_FORGET_ALL'))) return;
  await ContactMemoriesAPI.forgetAll(props.contactId);
  await load();
}

onMounted(load);
</script>

<template>
  <div class="contact-memories">
    <div v-if="loading">{{ t('CAPTAIN.MEMORY.LOADING') }}</div>
    <div v-else-if="error" class="error">{{ error }}</div>
    <div v-else-if="!memories.length" class="empty">
      {{ t('CAPTAIN.MEMORY.EMPTY') }}
    </div>
    <ul v-else>
      <li v-for="m in memories" :key="m.id" class="memory-row">
        <span class="type">{{ m.memory_type }}</span>
        <span class="content">{{ m.content }}</span>
        <span class="confidence">{{ Math.round(m.confidence * 100) }}%</span>
        <button @click="deleteMemory(m.id)">
          {{ t('CAPTAIN.MEMORY.FORGET') }}
        </button>
      </li>
    </ul>
    <button class="danger" @click="forgetAll">
      {{ t('CAPTAIN.MEMORY.FORGET_ALL') }}
    </button>
  </div>
</template>
