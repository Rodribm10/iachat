import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useInboxSignatures } from '../useInboxSignatures';

const mockInboxSignaturesAPI = vi.hoisted(() => ({
  getAll: vi.fn(),
  get: vi.fn(),
  upsert: vi.fn(),
  delete: vi.fn(),
}));

vi.mock('dashboard/api/inboxSignatures', () => ({
  default: mockInboxSignaturesAPI,
}));

const DEFAULT_USER = {
  message_signature: '<p>Global Signature</p>',
  ui_settings: {
    signature_position: 'bottom',
    signature_separator: '--',
  },
};

// Mutavel para os testes da assinatura automatica, que precisam de um usuario
// sem assinatura escrita. Restaurado no beforeEach.
const mockUser = vi.hoisted(() => ({ current: null }));

vi.mock('dashboard/composables/store', () => ({
  useStoreGetters: () => ({
    getCurrentUser: {
      get value() {
        return mockUser.current;
      },
    },
    getCurrentAccountId: {
      value: 1,
    },
  }),
}));

describe('useInboxSignatures', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUser.current = { ...DEFAULT_USER };
    const { _resetForTesting } = useInboxSignatures();
    _resetForTesting();
  });

  describe('fetchInboxSignatures', () => {
    it('fetches and caches inbox signatures', async () => {
      const mockData = [
        {
          inbox_id: 1,
          message_signature: '<p>Inbox 1 Sig</p>',
          signature_position: 'top',
          signature_separator: 'blank',
        },
        {
          inbox_id: 2,
          message_signature: '<p>Inbox 2 Sig</p>',
          signature_position: 'bottom',
          signature_separator: '--',
        },
      ];

      mockInboxSignaturesAPI.getAll.mockResolvedValue({ data: mockData });

      const { fetchInboxSignatures, inboxSignatures, hasFetched } =
        useInboxSignatures();
      await fetchInboxSignatures();

      expect(mockInboxSignaturesAPI.getAll).toHaveBeenCalled();
      expect(inboxSignatures.value[1].message_signature).toBe(
        '<p>Inbox 1 Sig</p>'
      );
      expect(inboxSignatures.value[2].message_signature).toBe(
        '<p>Inbox 2 Sig</p>'
      );
      expect(hasFetched.value).toBe(true);
    });
  });

  describe('getSignatureForInbox', () => {
    it('returns inbox-specific signature when available', async () => {
      mockInboxSignaturesAPI.getAll.mockResolvedValue({
        data: [
          {
            inbox_id: 1,
            message_signature: '<p>Inbox 1 Sig</p>',
            signature_position: 'top',
            signature_separator: 'blank',
          },
        ],
      });

      const { fetchInboxSignatures, getSignatureForInbox } =
        useInboxSignatures();
      await fetchInboxSignatures();

      expect(getSignatureForInbox(1)).toBe('<p>Inbox 1 Sig</p>');
    });

    it('falls back to global signature when no inbox-specific override', async () => {
      mockInboxSignaturesAPI.getAll.mockResolvedValue({ data: [] });

      const { fetchInboxSignatures, getSignatureForInbox } =
        useInboxSignatures();
      await fetchInboxSignatures();

      expect(getSignatureForInbox(999)).toBe('<p>Global Signature</p>');
    });
  });

  describe('getSignatureSettingsForInbox', () => {
    it('returns inbox-specific settings when available', async () => {
      mockInboxSignaturesAPI.getAll.mockResolvedValue({
        data: [
          {
            inbox_id: 1,
            message_signature: '<p>Sig</p>',
            signature_position: 'top',
            signature_separator: 'blank',
          },
        ],
      });

      const { fetchInboxSignatures, getSignatureSettingsForInbox } =
        useInboxSignatures();
      await fetchInboxSignatures();

      const settings = getSignatureSettingsForInbox(1);
      expect(settings.position).toBe('top');
      expect(settings.separator).toBe('blank');
    });

    it('falls back to global user settings when no inbox-specific override', async () => {
      mockInboxSignaturesAPI.getAll.mockResolvedValue({ data: [] });

      const { fetchInboxSignatures, getSignatureSettingsForInbox } =
        useInboxSignatures();
      await fetchInboxSignatures();

      const settings = getSignatureSettingsForInbox(999);
      expect(settings.position).toBe('bottom');
      expect(settings.separator).toBe('--');
    });
  });

  describe('upsertInboxSignature', () => {
    it('updates the cache after upserting', async () => {
      mockInboxSignaturesAPI.getAll.mockResolvedValue({ data: [] });
      mockInboxSignaturesAPI.upsert.mockResolvedValue({
        data: {
          inbox_id: 3,
          message_signature: '<p>New Sig</p>',
          signature_position: 'top',
          signature_separator: 'blank',
        },
      });

      const {
        fetchInboxSignatures,
        upsertInboxSignature,
        getSignatureForInbox,
      } = useInboxSignatures();
      await fetchInboxSignatures();

      await upsertInboxSignature(3, {
        message_signature: '<p>New Sig</p>',
        signature_position: 'top',
        signature_separator: 'blank',
      });

      expect(getSignatureForInbox(3)).toBe('<p>New Sig</p>');
    });
  });

  describe('deleteInboxSignature', () => {
    it('removes from cache after deleting', async () => {
      mockInboxSignaturesAPI.getAll.mockResolvedValue({
        data: [
          {
            inbox_id: 1,
            message_signature: '<p>Sig</p>',
            signature_position: 'top',
            signature_separator: 'blank',
          },
        ],
      });
      mockInboxSignaturesAPI.delete.mockResolvedValue({});

      const {
        fetchInboxSignatures,
        deleteInboxSignature,
        hasInboxSignature,
        getSignatureForInbox,
      } = useInboxSignatures();
      await fetchInboxSignatures();

      expect(hasInboxSignature(1)).toBe(true);

      await deleteInboxSignature(1);

      expect(hasInboxSignature(1)).toBe(false);
      // Falls back to global
      expect(getSignatureForInbox(1)).toBe('<p>Global Signature</p>');
    });
  });

  describe('autoSignature', () => {
    it('prefers the display name', () => {
      mockUser.current = {
        display_name: 'Duda',
        name: 'Maria Eduarda Souza',
      };
      const { autoSignature } = useInboxSignatures();
      expect(autoSignature.value).toBe('**Duda**');
    });

    it('falls back to the first name when there is no display name', () => {
      mockUser.current = { name: 'Rodrigo Borba Machado' };
      const { autoSignature } = useInboxSignatures();
      expect(autoSignature.value).toBe('**Rodrigo**');
    });

    it('ignores a display name that is only whitespace', () => {
      mockUser.current = { display_name: '   ', name: 'Rodrigo Borba' };
      const { autoSignature } = useInboxSignatures();
      expect(autoSignature.value).toBe('**Rodrigo**');
    });

    it('is empty when the agent has no name at all', () => {
      mockUser.current = {};
      const { autoSignature } = useInboxSignatures();
      expect(autoSignature.value).toBe('');
    });

    it('signs with the automatic name when nothing was written', () => {
      mockUser.current = { name: 'Rodrigo Borba Machado' };
      const { getSignatureForInbox } = useInboxSignatures();
      expect(getSignatureForInbox(1)).toBe('**Rodrigo**');
    });

    it('never overrides a signature the agent wrote', () => {
      mockUser.current = {
        name: 'Rodrigo Borba Machado',
        message_signature: '<p>Global Signature</p>',
      };
      const { getSignatureForInbox } = useInboxSignatures();
      expect(getSignatureForInbox(1)).toBe('<p>Global Signature</p>');
    });
  });
});
