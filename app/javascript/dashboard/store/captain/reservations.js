import CaptainReservationsAPI from 'dashboard/api/captain/reservations';
import { createStore } from '../storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export default createStore({
  name: 'CaptainReservation',
  API: CaptainReservationsAPI,
  mutations: {
    SET_CAPTAINRESERVATION_META(state, meta) {
      state.meta = {
        ...state.meta,
        totalCount: Number(meta.total_count),
        page: Number(meta.page),
        statusCounts: meta.status_counts || meta.statusCounts || {},
      };
    },
  },
  actions: mutations => ({
    fetchRevenue: async function fetchRevenue(_, params = {}) {
      try {
        const response = await CaptainReservationsAPI.revenue(params);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      }
    },
    create: async function create(_, data) {
      try {
        const response = await CaptainReservationsAPI.create(data);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      }
    },
    fetchPix: async function fetchPix({ commit }, reservationId) {
      commit(mutations.SET_UI_FLAG, { fetchingItem: true });
      try {
        const response = await CaptainReservationsAPI.pix(reservationId);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        commit(mutations.SET_UI_FLAG, { fetchingItem: false });
      }
    },
    cancel: async function cancel(_, { id, reason = '' }) {
      try {
        const response = await CaptainReservationsAPI.cancel(id, reason);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      }
    },
    markAsPaid: async function markAsPaid(_, { id, note = '' }) {
      try {
        const response = await CaptainReservationsAPI.markAsPaid(id, note);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      }
    },
    regeneratePix: async function regeneratePix(_, id) {
      try {
        const response = await CaptainReservationsAPI.regeneratePix(id);
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      }
    },
  }),
});
