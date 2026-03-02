import notificationTemplatesAPI from '../../api/captain/notificationTemplates';

const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isSaving: false,
  },
};

const getters = {
  getRecords: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  async fetch({ commit }, inboxId) {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await notificationTemplatesAPI.getAll(inboxId);
      commit('SET_RECORDS', data);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  async create({ commit }, { inboxId, payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await notificationTemplatesAPI.create(inboxId, payload);
      commit('ADD_RECORD', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async update({ commit }, { inboxId, id, payload }) {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await notificationTemplatesAPI.update(
        inboxId,
        id,
        payload
      );
      commit('UPDATE_RECORD', data);
      return data;
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  async delete({ commit }, { inboxId, id }) {
    await notificationTemplatesAPI.delete(inboxId, id);
    commit('DELETE_RECORD', id);
  },
};

const mutations = {
  SET_RECORDS($state, records) {
    $state.records = records;
  },
  ADD_RECORD($state, record) {
    $state.records.push(record);
  },
  UPDATE_RECORD($state, record) {
    const idx = $state.records.findIndex(r => r.id === record.id);
    if (idx !== -1) $state.records.splice(idx, 1, record);
  },
  DELETE_RECORD($state, id) {
    $state.records = $state.records.filter(r => r.id !== id);
  },
  SET_UI_FLAG($state, flags) {
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
