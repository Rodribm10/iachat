import * as MutationTypes from '../mutation-types';
import ApiClient from '../../api';

const captainReportsAPI = {
  getOperational: (accountId, params) =>
    ApiClient.get(`/api/v1/accounts/${accountId}/captain/reports/operational`, {
      params,
    }),
  getInsights: (accountId, params) =>
    ApiClient.get(`/api/v1/accounts/${accountId}/captain/reports/insights`, {
      params,
    }),
  getInsight: (accountId, id) =>
    ApiClient.get(
      `/api/v1/accounts/${accountId}/captain/reports/insights/${id}`
    ),
  generateInsight: (accountId, data) =>
    ApiClient.post(
      `/api/v1/accounts/${accountId}/captain/reports/insights/generate`,
      data
    ),
};

const state = {
  operational: null,
  insights: [],
  currentInsight: null,
  uiFlags: {
    isFetchingOperational: false,
    isFetchingInsights: false,
    isGenerating: false,
  },
};

export const getters = {
  getOperational: $state => $state.operational,
  getInsights: $state => $state.insights,
  getCurrentInsight: $state => $state.currentInsight,
  getUIFlags: $state => $state.uiFlags,
};

export const mutations = {
  [MutationTypes.SET_CAPTAIN_REPORTS_OPERATIONAL]($state, data) {
    $state.operational = data;
  },
  [MutationTypes.SET_CAPTAIN_REPORTS_INSIGHTS]($state, data) {
    $state.insights = data;
  },
  [MutationTypes.SET_CAPTAIN_REPORTS_CURRENT_INSIGHT]($state, data) {
    $state.currentInsight = data;
  },
  [MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS]($state, flags) {
    $state.uiFlags = { ...$state.uiFlags, ...flags };
  },
};

export const actions = {
  async fetchOperational({ commit, rootGetters }, params = {}) {
    const accountId = rootGetters['auth/getCurrentAccountId'];
    commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
      isFetchingOperational: true,
    });
    try {
      const { data } = await captainReportsAPI.getOperational(
        accountId,
        params
      );
      commit(MutationTypes.SET_CAPTAIN_REPORTS_OPERATIONAL, data);
    } finally {
      commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
        isFetchingOperational: false,
      });
    }
  },

  async fetchInsights({ commit, rootGetters }, params = {}) {
    const accountId = rootGetters['auth/getCurrentAccountId'];
    commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
      isFetchingInsights: true,
    });
    try {
      const { data } = await captainReportsAPI.getInsights(accountId, params);
      commit(MutationTypes.SET_CAPTAIN_REPORTS_INSIGHTS, data);
    } finally {
      commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
        isFetchingInsights: false,
      });
    }
  },

  async generateInsight({ commit, dispatch, rootGetters }, payload) {
    const accountId = rootGetters['auth/getCurrentAccountId'];
    commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, { isGenerating: true });
    try {
      await captainReportsAPI.generateInsight(accountId, payload);
      await dispatch('fetchInsights', { unit_id: payload.unit_id });
    } finally {
      commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
        isGenerating: false,
      });
    }
  },
};

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
