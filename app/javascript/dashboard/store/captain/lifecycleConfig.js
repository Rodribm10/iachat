import CaptainLifecycleConfigAPI from 'dashboard/api/captain/lifecycleConfig';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export const types = {
  SET_CONFIG: 'SET_LIFECYCLE_CONFIG',
  SET_UI_FLAG: 'SET_LIFECYCLE_CONFIG_UI_FLAG',
};

const state = {
  config: {},
  uiFlags: {
    fetching: false,
    updating: false,
  },
};

const getters = {
  getConfig: $state => $state.config,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  fetch: async ({ commit }) => {
    commit(types.SET_UI_FLAG, { fetching: true });
    try {
      const response = await CaptainLifecycleConfigAPI.show();
      commit(types.SET_CONFIG, response.data);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { fetching: false });
    }
  },
  update: async ({ commit }, data) => {
    commit(types.SET_UI_FLAG, { updating: true });
    try {
      const response = await CaptainLifecycleConfigAPI.update(data);
      commit(types.SET_CONFIG, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.SET_UI_FLAG, { updating: false });
    }
  },
};

const mutations = {
  [types.SET_CONFIG]($state, config) {
    $state.config = config;
  },
  [types.SET_UI_FLAG]($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
