import { defineStore } from 'pinia'
import { getAdminProvider } from '@admin-provider'
export const useAdminStore = defineStore('admin-mock-session', {
  state: () => ({ identity: getAdminProvider().identity(), sites: [], siteId: '', revision: 0, notice: '', leaveGuard: null, assignmentIntent: null, maintenanceIntent: null }),
  actions: {
    clear() { this.leaveGuard = null; this.assignmentIntent = null; this.maintenanceIntent = null; this.identity = getAdminProvider().identity(); this.sites = []; this.siteId = ''; this.revision++ },
    confirmLeave() { return !this.leaveGuard || this.leaveGuard() },
    selectSite(id) { if (this.siteId !== id) { getAdminProvider().changeContext(); this.siteId = id; this.revision++ } }
  }
})
