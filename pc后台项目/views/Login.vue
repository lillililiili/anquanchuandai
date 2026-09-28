<template>
  <main class="login-page">
    <section class="login-intro" aria-labelledby="login-platform-title">
      <img class="login-background" :src="loginBackground" alt="" fetchpriority="high" />
      <div class="brand"><span class="rl-brand" role="img" aria-label="融瓴 ROLLING"><img class="rl-brand-mark" src="/assets/brand-mark.svg" alt="" width="42" height="42" /><span class="rl-brand-type" aria-hidden="true"><b class="rl-brand-name">融瓴</b><span class="rl-brand-en">ROLLING</span></span></span><span class="brand-product">智能穿戴设备平台<small>管理中心</small></span></div>
      <div class="login-intro-copy">
        <span class="eyebrow">智能穿戴 · 安全管理</span>
        <h1 id="login-platform-title">让装备管理有序<br>让作业安全可依</h1>
        <p>统一管理人员与装备，让每一次领用、<br class="login-copy-break">每一项维护都有据可查。</p>
      </div>
      <p class="login-foot">人员档案<span>·</span>装备资产<span>·</span>运维管理</p>
    </section>
    <div class="login-side"><section class="login-card" aria-labelledby="login-heading">
      <span class="login-kicker">管理中心</span>
      <h2 id="login-heading">欢迎登录</h2><p class="muted">请使用您的管理账号进入平台</p>
      <form :aria-busy="busy" @submit.prevent="enter">
        <label class="login-field" for="admin-username">账号<span class="login-input"><User aria-hidden="true" /><input id="admin-username" v-model="username" name="username" autocomplete="username" placeholder="请输入管理账号" required :disabled="busy" :aria-describedby="error ? 'login-error' : undefined" /></span></label>
        <div class="login-field"><label for="admin-password">密码</label><span class="password-field login-input"><Lock aria-hidden="true" /><input id="admin-password" v-model="password" name="password" autocomplete="current-password" :type="visible ? 'text' : 'password'" placeholder="请输入密码" required :disabled="busy" :aria-describedby="error ? 'login-error' : undefined" /><button class="password-toggle" type="button" :aria-label="visible ? '隐藏密码' : '显示密码'" :title="visible ? '隐藏密码' : '显示密码'" :aria-pressed="visible" :disabled="busy" @click="visible = !visible"><component :is="visible ? View : Hide" aria-hidden="true" /></button></span></div>
        <p v-if="error" id="login-error" class="notice error" role="alert">{{ error }}</p>
        <p v-if="store.notice" class="notice" role="status">{{ store.notice }}</p>
        <button class="button primary enter" :disabled="busy" type="submit">{{ busy ? '正在登录…' : '登录' }}<Right v-if="!busy" aria-hidden="true" /></button>
      </form>
      <p class="login-help">账号或权限问题，请联系系统管理员</p>
    </section><p class="login-version">融瓴 ROLLING · 智能穿戴设备平台</p></div>
  </main>
</template>
<script setup>
import { ref } from 'vue'
import { View, Hide, User, Lock, Right } from '@element-plus/icons-vue'
import loginBackground from '../assets/visual/login-industrial.webp'
import { useRoute, useRouter } from 'vue-router'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
import { safeTarget } from '../navigation'
const provider = getAdminProvider(), store = useAdminStore(), route = useRoute(), router = useRouter()
const username = ref(''), password = ref(''), visible = ref(false), busy = ref(false), error = ref('')
async function enter() {
  if (busy.value) return
  if (!username.value.trim() || !password.value) { error.value = '请输入账号和密码'; return }
  busy.value = true; error.value = ''
  try {
    provider.login(username.value.trim(), password.value); store.clear(); store.notice = ''; password.value = ''
    const context = (await provider.query('context')).data
    const target = new URL(safeTarget(route.query.redirect), 'http://admin.local')
    if (target.searchParams.has('siteId') && !context.sites.some(s => s.id === target.searchParams.get('siteId'))) target.searchParams.delete('siteId')
    await router.replace(target.pathname + target.search)
  }
  catch (e) { error.value = e.message }
  finally { busy.value = false }
}
</script>
<style scoped>
.login-field { display: grid; gap: 10px; margin: 0 0 24px; font-weight: 500; }
.login-field .login-input input { width: 100%; min-width: 0; height: 48px; box-sizing: border-box; padding-left: 42px; font-weight: 400; border-color: #d7dee8; }
.login-input { position: relative; display: block; }
.login-input > svg { position: absolute; top: 15px; left: 14px; width: 18px; height: 18px; color: var(--muted); pointer-events: none; }
.password-field { position: relative; display: block; }
.login-field .password-field input { padding-right: 48px; }
.password-toggle { position: absolute; right: 1px; top: 1px; bottom: 1px; width: 44px; display: grid; place-items: center; border: 0; border-radius: 6px; background: transparent; color: var(--muted); padding: 0; cursor: pointer; }
.password-toggle svg { width: 20px; height: 20px; }
.password-toggle:hover:not(:disabled) { color: var(--blue-dark); background: var(--soft-blue); }
.password-toggle:focus-visible { outline: 2px solid var(--blue-dark); outline-offset: -3px; }
.password-toggle:disabled { background: transparent; cursor: not-allowed; }
</style>
