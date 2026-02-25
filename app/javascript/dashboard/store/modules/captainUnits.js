import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import CaptainUnitsAPI from '../../api/captain/units';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getUnits: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_CAPTAIN_UNITS_UI_FLAG, { isFetching: true });
    try {
      const response = await CaptainUnitsAPI.getUnits();
      commit(types.SET_CAPTAIN_UNITS, response.data);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SET_CAPTAIN_UNITS_UI_FLAG, { isFetching: false });
    }
  },

  create: async ({ commit }, unitObj) => {
    commit(types.SET_CAPTAIN_UNITS_UI_FLAG, { isCreating: true });
    try {
      const response = await CaptainUnitsAPI.createUnit(unitObj);
      commit(types.ADD_CAPTAIN_UNIT, response.data);
    } finally {
      commit(types.SET_CAPTAIN_UNITS_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...data }) => {
    commit(types.SET_CAPTAIN_UNITS_UI_FLAG, { isUpdating: true });
    try {
      const response = await CaptainUnitsAPI.updateUnit(id, data);
      commit(types.EDIT_CAPTAIN_UNIT, response.data);
    } finally {
      commit(types.SET_CAPTAIN_UNITS_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_CAPTAIN_UNITS_UI_FLAG, { isDeleting: true });
    try {
      await CaptainUnitsAPI.deleteUnit(id);
      commit(types.DELETE_CAPTAIN_UNIT, id);
    } finally {
      commit(types.SET_CAPTAIN_UNITS_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_CAPTAIN_UNITS_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },
  [types.SET_CAPTAIN_UNITS]: MutationHelpers.set,
  [types.ADD_CAPTAIN_UNIT]: MutationHelpers.create,
  [types.EDIT_CAPTAIN_UNIT]: MutationHelpers.update,
  [types.DELETE_CAPTAIN_UNIT]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
