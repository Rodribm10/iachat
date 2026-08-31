import { flushPromises, mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { defineComponent, h } from 'vue';
import GowaConfiguration from './GowaConfiguration.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const NextButtonStub = defineComponent({
  props: {
    label: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
  },
  emits: ['click'],
  setup(props, { emit }) {
    return () =>
      h(
        'button',
        { disabled: props.disabled, onClick: () => emit('click') },
        props.label
      );
  },
});

const mountComponent = () => {
  const store = createStore({
    getters: { getCurrentAccountId: () => 2 },
  });

  return mount(GowaConfiguration, {
    props: { inbox: { id: 25, account_id: 2 } },
    global: {
      plugins: [store],
      stubs: { NextButton: NextButtonStub },
      mocks: { $t: key => key },
    },
  });
};

describe('GowaConfiguration', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    window.axios = { get: vi.fn(), put: vi.fn(), post: vi.fn() };
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('expires the QR Code and stops polling instead of leaving a stale code on screen', async () => {
    window.axios.get.mockImplementation(url => {
      if (url.endsWith('/qr')) {
        return Promise.resolve({
          data: { qrcode: 'data:image/png;base64,qr-novo', expires_in: 10 },
        });
      }
      return Promise.resolve({
        data: { results: { is_connected: false, is_logged_in: false } },
      });
    });

    const wrapper = mountComponent();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();

    expect(wrapper.find('img').exists()).toBe(true);
    expect(wrapper.get('button').attributes('disabled')).toBeDefined();

    await vi.advanceTimersByTimeAsync(5_000);
    await flushPromises();

    expect(wrapper.text()).toContain('INBOX_MGMT.EDIT.GOWA.WAITING_CONNECTION');

    await vi.advanceTimersByTimeAsync(5_000);
    await flushPromises();

    expect(wrapper.find('img').exists()).toBe(false);
    expect(wrapper.text()).toContain('INBOX_MGMT.EDIT.GOWA.QR_EXPIRED');
    expect(wrapper.get('button').attributes('disabled')).toBeUndefined();
    wrapper.unmount();
  });

  it('re-registers the webhook once after the device connects', async () => {
    window.axios.get.mockResolvedValue({
      data: { results: { is_connected: true, is_logged_in: true } },
    });
    window.axios.put.mockResolvedValue({ data: { success: true } });

    const wrapper = mountComponent();
    await flushPromises();

    expect(window.axios.put).toHaveBeenCalledOnce();
    expect(window.axios.put).toHaveBeenCalledWith(
      '/api/v1/accounts/2/inboxes/25/gowa/update_webhook'
    );
    wrapper.unmount();
  });
});
