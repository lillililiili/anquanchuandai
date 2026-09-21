import { createApp } from 'vue'
import { ElMessage } from 'element-plus'
import 'element-plus/es/components/message/style/css'
import 'element-plus/theme-chalk/dark/css-vars.css'
import App from './App.vue'
import AppPagination from './components/AppPagination.vue'
import pinia from './store'
import router, { safeRedirect } from './router'
import { useUserStore } from './store/user'
import { setUnauthorizedHandler } from '@/utils/request'
import './styles/index.scss'
import './styles/personnel.scss'
import './styles/spatial.scss'
import './styles/video.scss'
import './styles/events.scss'
import './styles/v3-samples.scss'
import './styles/v3-workspaces.scss'
import './styles/workspace-layout.scss'
import './styles/v4-vivid.scss'
import './styles/v5-luminous.scss'
import './styles/v6-chromatic.scss'

const app = createApp(App)
app.component('AppPagination', AppPagination)
app.use(pinia)
setUnauthorizedHandler((requestToken) => {
  const user = useUserStore(pinia)
  // 首次清理后 token 为空，并发的后续 401 不再提示或导航。
  if (!user.token || requestToken !== user.token) return
  const redirect = safeRedirect(router.currentRoute.value.fullPath)
  user.clearSession()
  ElMessage.warning('登录状态已失效，请重新登录')
  router.replace({ name: 'login', query: { redirect } })
})
app.use(router)
app.mount('#app')
