import { defineStore } from 'pinia'
import { ref } from 'vue'
import * as authApi from '@/api/auth'
import { getToken, setToken, removeToken } from '@/utils/auth'
import { useContextStore } from '@/store/context'
import { clearDispatchSession } from '@dispatch-runtime'

export const useUserStore = defineStore('portal-user', () => {
  const token = ref(getToken())
  const user = ref(null)
  const roles = ref([])
  const permissions = ref([])
  const initialized = ref(false)
  let profilePromise = null
  let revision = 0

  function clearSession() {
    clearDispatchSession()
    useContextStore().reset()
    revision++
    token.value = ''
    user.value = null
    roles.value = []
    permissions.value = []
    initialized.value = false
    profilePromise = null
    removeToken()
  }

  async function loadProfile() {
    if (initialized.value) return
    if (profilePromise) return profilePromise
    const currentRevision = revision
    const pending = authApi.getInfo().then((data) => {
      if (currentRevision !== revision) throw new Error('会话已变更，请重新登录')
      if (!data.user || typeof data.user !== 'object') throw new Error('用户信息不完整，请联系管理员')
      user.value = data.user
      roles.value = Array.isArray(data.roles) ? data.roles : []
      permissions.value = Array.isArray(data.permissions) ? data.permissions : []
      initialized.value = true
    }).finally(() => { if (profilePromise === pending) profilePromise = null })
    profilePromise = pending
    return pending
  }

  async function signIn(credentials) {
    clearSession()
    const data = await authApi.login(credentials)
    if (typeof data.token !== 'string' || !data.token) throw new Error('登录响应未包含有效凭证，请联系管理员')
    token.value = data.token
    setToken(data.token)
    try { await loadProfile() } catch (error) { clearSession(); throw error }
  }

  async function signOut() {
    try { if (token.value) await authApi.logout() } finally { clearSession() }
  }

  return { token, user, roles, permissions, initialized, clearSession, loadProfile, signIn, signOut }
})
