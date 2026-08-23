import { ref, computed } from 'vue';
import { useStoreGetters } from 'dashboard/composables/store';
import inboxSignaturesAPI from 'dashboard/api/inboxSignatures';

const inboxSignatures = ref({});
const isFetching = ref(false);
const hasFetched = ref(false);

/**
 * Composable for managing per-inbox signatures.
 * Provides methods to fetch, upsert, and delete inbox-specific signatures,
 * with fallback to the global user signature.
 */
export function useInboxSignatures() {
  const getters = useStoreGetters();
  const currentUser = computed(() => getters.getCurrentUser.value);
  const currentAccountId = computed(() => getters.getCurrentAccountId.value);
  const globalSignature = computed(
    () => currentUser.value?.message_signature || ''
  );

  /**
   * Assinatura automatica de quem esta falando, usada quando a pessoa nunca
   * escreveu uma. Ordem de prioridade: nome de exibicao; na falta dele, o
   * primeiro nome do nome completo — "Rodrigo Borba Machado" assina "Rodrigo",
   * nao o nome inteiro.
   *
   * Vai em negrito markdown; os providers de WhatsApp convertem `**x**` para o
   * asterisco simples que o app usa (Whatsapp::Providers::BaseService).
   *
   * Quem nao quiser assinar desliga no botao da caixa de resposta — o padrao e
   * assinar, porque uma mensagem sem nome deixa o cliente sem saber com quem
   * esta falando.
   */
  const autoSignature = computed(() => {
    const user = currentUser.value || {};
    const displayName = (user.display_name || '').trim();
    const firstName = (user.name || '').trim().split(/\s+/)[0] || '';
    const name = displayName || firstName;
    return name ? `**${name}**` : '';
  });

  const fetchInboxSignatures = async ({ force = false } = {}) => {
    if (isFetching.value) return;
    if (hasFetched.value && !force) return;

    isFetching.value = true;
    try {
      const { data } = await inboxSignaturesAPI.getAll(currentAccountId.value);
      const signaturesMap = {};
      data.forEach(sig => {
        signaturesMap[sig.inbox_id] = sig;
      });
      inboxSignatures.value = signaturesMap;
      hasFetched.value = true;
    } catch {
      // Silently fail — fallback to global signature
    } finally {
      isFetching.value = false;
    }
  };

  const upsertInboxSignature = async (inboxId, params) => {
    const { data } = await inboxSignaturesAPI.upsert(inboxId, params);
    inboxSignatures.value = {
      ...inboxSignatures.value,
      [inboxId]: data,
    };
    return data;
  };

  const deleteInboxSignature = async inboxId => {
    await inboxSignaturesAPI.delete(inboxId);
    const updated = { ...inboxSignatures.value };
    delete updated[inboxId];
    inboxSignatures.value = updated;
  };

  /**
   * Returns the inbox-specific signature if it exists, otherwise the global
   * signature, otherwise the automatic one derived from the agent's name.
   */
  const getSignatureForInbox = inboxId => {
    const inboxSig = inboxSignatures.value[inboxId];
    return (
      inboxSig?.message_signature ||
      globalSignature.value ||
      autoSignature.value
    );
  };

  /**
   * Returns signature settings (position, separator) for the given inbox,
   * falling back to the user's global settings.
   */
  const getSignatureSettingsForInbox = inboxId => {
    const inboxSig = inboxSignatures.value[inboxId];
    if (inboxSig) {
      return {
        position: inboxSig.signature_position || 'top',
        separator: inboxSig.signature_separator || 'blank',
      };
    }
    const uiSettings = currentUser.value?.ui_settings || {};
    return {
      position: uiSettings.signature_position || 'top',
      separator: uiSettings.signature_separator || 'blank',
    };
  };

  /**
   * Returns the raw inbox signature record if one exists.
   */
  const getInboxSignature = inboxId => {
    return inboxSignatures.value[inboxId] || null;
  };

  /**
   * Checks if a specific inbox has a custom signature override.
   */
  const hasInboxSignature = inboxId => {
    return !!inboxSignatures.value[inboxId];
  };

  return {
    inboxSignatures: computed(() => inboxSignatures.value),
    isFetching: computed(() => isFetching.value),
    hasFetched: computed(() => hasFetched.value),
    fetchInboxSignatures,
    upsertInboxSignature,
    deleteInboxSignature,
    autoSignature,
    getSignatureForInbox,
    getSignatureSettingsForInbox,
    getInboxSignature,
    hasInboxSignature,
    _resetForTesting: () => {
      inboxSignatures.value = {};
      isFetching.value = false;
      hasFetched.value = false;
    },
  };
}
