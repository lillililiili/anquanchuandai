import { login, logout, getInfo } from '@/api/login'
import { getMe, selectCurrentSite } from '@/api/wear/identity'
import { getToken, setToken, removeToken } from '@/utils/auth'
import { hasAccessPermission, mergeAccessValues } from '@/store/access'
import defAva from '@/assets/images/profile.jpg'

const useUserStore = defineStore('user', {
  state: () => ({
    token: getToken(),
    name: '',
    avatar: '',
    roles: [],
    permissions: [],
    userId: '',
    sites: [],
    currentSiteId: '',
    isPlatformAdmin: false,
    requestEpoch: 0
  }),
  getters: {
    canWriteHat: (state) => hasAccessPermission(state.permissions, 'wear:hat:edit'),
    canWritePerson: (state) => hasAccessPermission(state.permissions, 'wear:person:edit'),
    canWriteDevice: (state) => hasAccessPermission(state.permissions, 'wear:device:edit'),
    canClaimEvent: (state) => hasAccessPermission(state.permissions, 'wear:event:claim'),
    canReviewEvent: (state) => hasAccessPermission(state.permissions, 'wear:event:review'),
    canStartCall: (state) => hasAccessPermission(state.permissions, 'wear:call:start'),
    canSendTts: (state) => hasAccessPermission(state.permissions, 'wear:command:tts'),
    canEditTask: (state) => hasAccessPermission(state.permissions, 'wear:task:edit'),
    canEditFence: (state) => hasAccessPermission(state.permissions, 'wear:fence:edit')
  },
  actions: {
    // 登录
    login(userInfo) {
      const username = userInfo.username.trim()
      const password = userInfo.password
      const code = userInfo.code
      const uuid = userInfo.uuid
      return new Promise((resolve, reject) => {
        login(username, password, code, uuid)
          .then(res => {
            setToken(res.token)
            this.token = res.token
            resolve()
          })
          .catch(error => {
            reject(error)
          })
      })
    },
    // 获取用户信息
    getInfo() {
      return new Promise((resolve, reject) => {
        getInfo()
          .then(res => {
            const user = res.user
            this.userId = user.userId
            const avatar =
              user.avatar == '' || user.avatar == null
                ? defAva
                : import.meta.env.VITE_APP_BASE_API + user.avatar

            if (res.roles && res.roles.length > 0) {
              // 验证返回的roles是否是一个非空数组
              this.roles = res.roles
              this.permissions = res.permissions
            } else {
              this.roles = ['ROLE_DEFAULT']
            }
            this.name = user.userName
            this.avatar = avatar
            this.loadIdentity()
              .then(() => resolve(res))
              .catch(error => reject(error))
          })
          .catch(error => {
            reject(error)
          })
      })
    },
    loadIdentity() {
      return getMe().then(res => {
        const me = res.data || {}
        this.sites = me.authorizedSites || []
        this.permissions = mergeAccessValues(this.permissions, me.permissions)
        this.isPlatformAdmin = !!me.admin
        if (me.roles && me.roles.length) {
          this.roles = Array.from(me.roles)
        }
        this.currentSiteId = me.currentSiteId || ''
        if (!this.currentSiteId && this.sites.length === 1) {
          return this.switchSite(this.sites[0].id).then(() => me)
        }
        if (!this.currentSiteId && this.sites.length > 1) {
          let last = ''
          try {
            last = localStorage.getItem('wear.currentSiteId') || ''
          } catch (e) {
            last = ''
          }
          if (last && this.sites.some(s => String(s.id) === String(last))) {
            return this.switchSite(last).then(() => me)
          }
        }
        return me
      })
    },
    switchSite(siteId) {
      this.requestEpoch += 1
      return selectCurrentSite(siteId).then(() => {
        this.currentSiteId = siteId
        try {
          localStorage.setItem('wear.currentSiteId', String(siteId))
        } catch (e) {}
      })
    },
    // 退出系统
    logOut() {
      return new Promise((resolve) => {
        logout(this.token)
          .catch(() => {})
          .finally(() => {
            this.token = ''
            this.roles = []
            this.permissions = []
            this.sites = []
            this.currentSiteId = ''
            this.isPlatformAdmin = false
            this.requestEpoch += 1
            removeToken()
            resolve()
          })
      })
    }
  }
})

export default useUserStore
