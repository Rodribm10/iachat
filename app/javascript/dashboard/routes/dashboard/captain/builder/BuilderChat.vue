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
      t('CAPTAIN_HERMES_BUILDER.SEND_FAILED', {
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
  if (!window.confirm(t('CAPTAIN_HERMES_BUILDER.RESET_CONFIRM'))) return;
  try {
    await hermesBuilderApi.reset();
    messages.value = [];
  } catch (e) {
    useAlert(t('CAPTAIN_HERMES_BUILDER.RESET_FAILED'));
  }
};

const startSession = async () => {
  if (sending.value) return;
  sending.value = true;
  try {
    await hermesBuilderApi.start();
  } catch (e) {
    useAlert(
      t('CAPTAIN_HERMES_BUILDER.SEND_FAILED', {
        message: e.response?.data?.error || e.message || 'unknown',
      })
    );
  } finally {
    sending.value = false;
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
  <div class="builder-wrapper">
    <header class="builder-header">
      <div>
        <h2>{{ t('CAPTAIN_HERMES_BUILDER.HEADER_TITLE') }}</h2>
        <p>{{ t('CAPTAIN_HERMES_BUILDER.HEADER_DESCRIPTION') }}</p>
      </div>
      <Button variant="ghost" size="sm" @click="resetSession">
        {{ t('CAPTAIN_HERMES_BUILDER.RESET') }}
      </Button>
    </header>

    <section ref="scrollContainer" class="messages">
      <div v-if="!messages.length" class="empty-state">
        <p>{{ t('CAPTAIN_HERMES_BUILDER.EMPTY_STATE') }}</p>
        <button
          type="button"
          class="start-button"
          :disabled="sending"
          @click="startSession"
        >
          {{ t('CAPTAIN_HERMES_BUILDER.START') }}
        </button>
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
        :placeholder="t('CAPTAIN_HERMES_BUILDER.PLACEHOLDER')"
        :disabled="sending"
        @keydown="handleKeydown"
      />
      <Button
        variant="primary"
        :disabled="!input.trim() || sending"
        @click="sendMessage"
      >
        {{ t('CAPTAIN_HERMES_BUILDER.SEND') }}
      </Button>
    </footer>

    <p v-if="sessionId" class="session-debug">
      {{ t('CAPTAIN_HERMES_BUILDER.SESSION_LABEL') }} {{ sessionId }}
    </p>
  </div>
</template>

<style scoped lang="scss">
// Corrigido em 22/08/2026. O componente usava variáveis CSS que NÃO EXISTEM
// nesta versão do Chatwoot (--color-background, --color-text-light,
// --color-border, --color-woot-500): todas caíam no fallback claro. No tema
// escuro isso dava fundo branco com texto herdando a cor clara do tema —
// branco no branco, impossível de ler enquanto se digita. Agora usa a paleta
// `n-` do dashboard, que já responde aos dois temas.
.builder-wrapper {
  display: flex;
  flex-direction: column;
  gap: 16px;
  height: calc(100vh - 260px);
  max-width: 900px;
  margin: 0 auto;
}

.builder-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  padding: 16px 20px;
  @apply bg-n-alpha-2;
  border-radius: 12px;

  h2 {
    margin: 0 0 4px;
    font-size: 18px;
    font-weight: 600;
  }

  p {
    margin: 0;
    @apply text-n-slate-11;
    font-size: 13px;
  }
}

.messages {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  @apply bg-n-background;
  border-radius: 12px;
  @apply border border-n-weak;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.empty-state {
  margin: auto;
  @apply text-n-slate-11;
  font-size: 14px;
  text-align: center;
  display: flex;
  flex-direction: column;
  gap: 16px;
  align-items: center;

  p {
    margin: 0;
  }
}

.start-button {
  @apply bg-n-brand text-white;
  border: none;
  padding: 10px 24px;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.15s;

  &:hover:not(:disabled) {
    opacity: 0.9;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
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
  @apply bg-n-solid-2 text-n-slate-12;
  font-size: 14px;

  .msg--user & {
    @apply bg-n-brand text-white;
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
    @apply bg-n-slate-10;
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
  align-items: flex-end;
  @apply bg-n-background;
  border-radius: 12px;
  @apply border border-n-weak;

  // O textarea nao tem borda propria; sem isto nao ha sinal visivel de foco.
  &:focus-within {
    @apply border-n-brand;
  }

  textarea {
    flex: 1;
    border: none;
    resize: none;
    outline: none;
    font: inherit;
    background: transparent;
    // Era `color: inherit`: puxava a cor clara do tema escuro por cima do
    // fundo branco do fallback. Texto branco em fundo branco.
    @apply text-n-slate-12;

    &::placeholder {
      @apply text-n-slate-10;
    }
  }
}

.session-debug {
  font-size: 11px;
  @apply text-n-slate-11;
  text-align: right;
  margin: 0;
}
</style>
