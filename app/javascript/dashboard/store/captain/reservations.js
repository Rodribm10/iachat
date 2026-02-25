import CaptainReservationsAPI from 'dashboard/api/captain/reservations';
import { createStore } from '../storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';

export default createStore({
  name: 'CaptainReservation',
  API: CaptainReservationsAPI,
  actions: mutations => ({
    fetchRevenue: async function fetchRevenue(_, params = {}) {
      try {
        const response = await CaptainReservationsAPI.revenue(params);
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
  }),
});
