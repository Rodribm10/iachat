<script setup>
import {
  ref,
  computed,
  onMounted,
  onBeforeUnmount,
  nextTick,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import hermesBuilderApi from 'dashboard/api/captain/hermesBuilder';

const { t } = useI18n();

const messages = ref([]);
const input = ref('');
const sending = ref(false);
const polling = ref(null);
const scrollContainer = ref(null);
const sessionId = ref(null);

const lastMessageRole = computed(() => messages.value.at(-1)?.role || null);
const isWaiting = computed(
  () => sending.value || lastMessageRole.value === 'user'
);

const scrollToBottom = () => {
  const el = scrollContainer.value;
  if (el) el.scrollTop = el.scrollHeight;
};

const fetchMessages = async () => {
  try {
    const { data } = await hermesBuilderApi.fetchMessages();
    messages.value = data.messages || [];
    sessionId.value = data.session_id;
    await nextTick();
    scrollToBottom();
  } catch (e) {
    // silencioso — polling repete
  }
};

const sendMessage = async () => {
  const text = input.value.trim();
  if (!text || sending.value) return;
  sending.value = true;
  // optimistic UI
  messages.value.push({
    role: 'user',
    content: text,
    created_at: new Date().toISOString(),
  });
  input.value = '';
  await nextTick();
  scrollToBottom();
  try {
    await hermesBuilderApi.sendMessage(text);
  } catch (e) {
    useAlert(
      t('CAPTAIN.HERMES_BUILDER.SEND_FAILED', {
        message: e.response?.data?.error || e.message || 'unknown',
      })
    );
  } finally {
    sending.value = false;
  }
};

const handleKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
};

const resetSession = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CAPTAIN.HERMES_BUILDER.RESET_CONFIRM'))) return;
  try {
    await hermesBuilderApi.reset();
    messages.value = [];
  } catch (e) {
    useAlert(t('CAPTAIN.HERMES_BUILDER.RESET_FAILED'));
  }
};

const formatTime = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
};

onMounted(() => {
  fetchMessages();
  polling.value = setInterval(fetchMessages, 2000);
});

onBeforeUnmount(() => {
  if (polling.value) clearInterval(polling.value);
});

watch(messages, () => nextTick().then(scrollToBottom), { deep: true });
</script>

<template>
  <PageLayout
    :title="t('CAPTAIN.HERMES_BUILDER.TITLE')"
    :description="t('CAPTAIN.HERMES_BUILDER.DESCRIPTION')"
  >
    <div class="builder-wrapper">
      <header class="builder-header">
        <div>
          <h2>{{ t('CAPTAIN.HERMES_BUILDER.HEADER_TITLE') }}</h2>
          <p>{{ t('CAPTAIN.HERMES_BUILDER.HEADER_DESCRIPTION') }}</p>
        </div>
        <Button variant="ghost" size="sm" @click="resetSession">
          {{ t('CAPTAIN.HERMES_BUILDER.RESET') }}
        </Button>
      </header>

      <section ref="scrollContainer" class="messages">
        <div v-if="!messages.length" class="empty-state">
          {{ t('CAPTAIN.HERMES_BUILDER.EMPTY_STATE') }}
        </div>
        <div
          v-for="(msg, idx) in messages"
          :key="idx"
          class="msg"
          :class="[`msg--${msg.role}`]"
        >
          <div class="msg__bubble">
            <div class="msg__content">{{ msg.content }}</div>
            <div class="msg__meta">{{ formatTime(msg.created_at) }}</div>
          </div>
        </div>
        <div v-if="isWaiting" class="msg msg--construtor">
          <div class="msg__bubble msg__bubble--typing">
            <span class="dot" /><span class="dot" /><span class="dot" />
          </div>
        </div>
      </section>

      <footer class="composer">
        <textarea
          v-model="input"
          rows="2"
          :placeholder="t('CAPTAIN.HERMES_BUILDER.PLACEHOLDER')"
          :disabled="sending"
          @keydown="handleKeydown"
        />
        <Button
          variant="primary"
          :disabled="!input.trim() || sending"
          @click="sendMessage"
        >
          {{ t('CAPTAIN.HERMES_BUILDER.SEND') }}
        </Button>
      </footer>

      <p v-if="sessionId" class="session-debug">
        {{ t('CAPTAIN.HERMES_BUILDER.SESSION_LABEL') }} {{ sessionId }}
      </p>
    </div>
  </PageLayout>
</template>

<style scoped lang="scss">
.builder-wrapper {
  display: flex;
  flex-direction: column;
  gap: 16px;
  height: calc(100vh - 220px);
  max-width: 900px;
  margin: 0 auto;
}

.builder-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  padding: 16px 20px;
  background: var(--color-background-light, #f7f8fa);
  border-radius: 12px;

  h2 {
    margin: 0 0 4px;
    font-size: 18px;
    font-weight: 600;
  }

  p {
    margin: 0;
    color: var(--color-text-light, #6b7280);
    font-size: 13px;
  }
}

.messages {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  background: var(--color-background, #fff);
  border-radius: 12px;
  border: 1px solid var(--color-border, #e5e7eb);
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.empty-state {
  margin: auto;
  color: var(--color-text-light, #9ca3af);
  font-size: 14px;
  text-align: center;
}

.msg {
  display: flex;

  &--user {
    justify-content: flex-end;
  }

  &--construtor {
    justify-content: flex-start;
  }
}

.msg__bubble {
  max-width: 70%;
  padding: 10px 14px;
  border-radius: 14px;
  background: var(--color-background-light, #f3f4f6);
  font-size: 14px;

  .msg--user & {
    background: var(--color-woot-500, #1f93ff);
    color: #fff;
  }
}

.msg__content {
  white-space: pre-wrap;
  word-break: break-word;
}

.msg__meta {
  font-size: 11px;
  margin-top: 4px;
  opacity: 0.7;
}

.msg__bubble--typing {
  display: flex;
  gap: 4px;
  padding: 12px 16px;

  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--color-text-light, #6b7280);
    animation: typing 1.4s infinite ease-in-out;

    &:nth-child(2) {
      animation-delay: 0.2s;
    }
    &:nth-child(3) {
      animation-delay: 0.4s;
    }
  }
}

@keyframes typing {
  0%,
  60%,
  100% {
    opacity: 0.3;
    transform: translateY(0);
  }
  30% {
    opacity: 1;
    transform: translateY(-3px);
  }
}

.composer {
  display: flex;
  gap: 8px;
  padding: 12px;
  background: var(--color-background, #fff);
  border-radius: 12px;
  border: 1px solid var(--color-border, #e5e7eb);

  textarea {
    flex: 1;
    border: none;
    resize: none;
    outline: none;
    font: inherit;
    background: transparent;
    color: inherit;
  }
}

.session-debug {
  font-size: 11px;
  color: var(--color-text-light, #9ca3af);
  text-align: right;
  margin: 0;
}
</style>
