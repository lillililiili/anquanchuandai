<template>
  <main class="login-page">
    <section class="login-intro">
      <div class="brand"><span class="brand-mark" aria-hidden="true">W</span><span>智能穿戴设备平台<small>管理中心</small></span></div>
      <span class="eyebrow">WEARABLE EQUIPMENT / ADMINISTRATION</span>
      <h1>智能穿戴设备平台<br><span>管理中心</span></h1>
      <p>人员、资产、领用和运维，围绕同一份管理事实展开。</p>
      <p class="login-foot">装备概念示意 · 不代表确认型号或真实设备接入</p>
    </section>
    <div class="login-side"><section class="login-card">
      <h2>管理账号登录</h2><p class="muted">请使用管理账号登录</p>
      <form @submit.prevent="enter">
        <label class="login-field">账号<input v-model="username" name="username" autocomplete="username" placeholder="请输入管理账号" required :disabled="busy" /></label>
        <div class="login-field"><label for="admin-password">密码</label><span class="password-field"><input id="admin-password" v-model="password" name="password" autocomplete="current-password" :type="visible ? 'text' : 'password'" placeholder="请输入密码" required :disabled="busy" /><button class="password-toggle" type="button" :aria-label="visible ? '隐藏密码' : '显示密码'" :title="visible ? '隐藏密码' : '显示密码'" :aria-pressed="visible" :disabled="busy" @click="visible = !visible"><component :is="visible ? View : Hide" aria-hidden="true" /></button></span></div>
        <p v-if="error" class="error" role="alert">{{ error }}</p>
        <p v-if="store.notice" class="notice" role="status">{{ store.notice }}</p>
        <button class="button primary enter" :disabled="busy" type="submit">{{ busy ? '正在登录…' : '登录' }}</button>
      </form>
    </section><p class="login-version">资产建档 · 发放回收 · 维修退役 · 历史追溯</p></div>
  </main>
</template>
<script setup>
import { ref } from 'vue'
import { View, Hide } from '@element-plus/icons-vue'
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
.login-field { display: grid; gap: 10px; margin: 24px 0; font-weight: 600; }
.login-field input { width: 100%; min-width: 0; min-height: 46px; box-sizing: border-box; }
.password-field { position: relative; display: block; }
.password-field input { padding-right: 48px; }
.password-toggle { position: absolute; right: 1px; top: 1px; bottom: 1px; width: 44px; display: grid; place-items: center; border: 0; border-radius: 6px; background: transparent; color: var(--muted); padding: 0; cursor: pointer; }
.password-toggle svg { width: 20px; height: 20px; }
.password-toggle:hover:not(:disabled) { color: var(--blue-dark); background: var(--soft-blue); }
.password-toggle:focus-visible { outline: 2px solid var(--blue-dark); outline-offset: -3px; }
.password-toggle:disabled { background: transparent; cursor: not-allowed; }
</style>
