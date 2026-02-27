import * as MutationTypes from '../mutation-types';
import CaptainReportsAPI from '../../api/captain/reports';

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
  async fetchOperational({ commit }, params = {}) {
    commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
      isFetchingOperational: true,
    });
    try {
      const { data } = await CaptainReportsAPI.getOperational(params);
      commit(MutationTypes.SET_CAPTAIN_REPORTS_OPERATIONAL, data);
    } finally {
      commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
        isFetchingOperational: false,
      });
    }
  },

  async fetchInsights({ commit }, params = {}) {
    commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
      isFetchingInsights: true,
    });
    try {
      const { data } = await CaptainReportsAPI.getInsights(params);
      commit(MutationTypes.SET_CAPTAIN_REPORTS_INSIGHTS, data);
    } finally {
      commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
        isFetchingInsights: false,
      });
    }
  },

  async generateInsight({ commit, dispatch }, params) {
    commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, { isGenerating: true });
    try {
      await CaptainReportsAPI.generateInsight(params);
      await dispatch('fetchInsights', params);
    } finally {
      commit(MutationTypes.SET_CAPTAIN_REPORTS_UI_FLAGS, {
        isGenerating: false,
      });
    }
  },
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

export default {
  namespaced: true,
  state,
  getters,
  mutations,
  actions,
};
