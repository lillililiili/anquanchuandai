<script setup>
import { onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import BrandMark from '@/components/BrandMark.vue'
import AppIcon from '@/components/AppIcon.vue'
import LoginAurora from '@/components/LoginAurora.vue'
import HudFrame from '@/components/HudFrame.vue'
import { getCaptcha } from '@/api/auth'
import { useUserStore } from '@/store/user'
import { safeRedirect } from '@/router'

const route = useRoute()
const router = useRouter()
const user = useUserStore()
const title = import.meta.env.VITE_APP_TITLE
const form = reactive({ username: '', password: '', code: '', uuid: '' })
const formRef = ref()
const passwordVisible = ref(false)
const submitting = ref(false)
const captchaLoading = ref(false)
const captchaReady = ref(false)
const captchaEnabled = ref(false)
const captchaImage = ref('')
const captchaError = ref('')
const errorMessage = ref('')
const errorRef = ref()
const rules = {
  username: [{ required: true, whitespace: true, message: '请输入工作账号', trigger: 'blur' }],
  password: [{ required: true, message: '请输入密码', trigger: 'blur' }],
  code: [{ validator: (_rule, value, callback) => callback(captchaEnabled.value && !value.trim() ? new Error('请输入图形验证码') : undefined), trigger: 'blur' }]
}

async function refreshCaptcha() {
  if (captchaLoading.value || submitting.value) return
  captchaLoading.value = true
  captchaReady.value = false
  captchaError.value = ''
  form.code = ''
  form.uuid = ''
  captchaImage.value = ''
  try {
    const data = await getCaptcha()
    captchaEnabled.value = data.captchaEnabled !== false
    if (captchaEnabled.value) {
      if (!data.img || !data.uuid) throw new Error('验证码响应不完整，请刷新重试')
      captchaImage.value = `data:image/jpeg;base64,${data.img}`
      form.uuid = data.uuid
    }
    captchaReady.value = true
  } catch (error) { captchaError.value = error.message }
  finally { captchaLoading.value = false }
}

function captchaImageFailed() {
  captchaReady.value = false
  captchaError.value = '验证码图片加载失败，请刷新重试'
}

async function submit() {
  if (submitting.value || !captchaReady.value) return
  if (!await formRef.value.validate().catch(() => false)) return
  submitting.value = true
  errorMessage.value = ''
  try {
    await user.signIn({ ...form, username: form.username.trim() })
    form.password = ''
    await router.replace(safeRedirect(route.query.redirect))
  } catch (error) {
    errorMessage.value = error.message
    submitting.value = false
    await refreshCaptcha()
    errorRef.value?.focus()
  } finally { submitting.value = false }
}

onMounted(refreshCaptcha)
</script>

<template>
  <main class="login-page">
    <LoginAurora />
    <header class="login-brand"><BrandMark /></header>
    <section class="login-intro" aria-label="平台介绍">
      <span class="login-kicker">智能穿戴 · 现场安全协同</span>
      <h1>{{ title }}</h1>
      <p>让每一份守护，<br />看得见，连得起。</p>
      <div class="login-domains"><span>人员感知</span><span>装备协同</span><span>作业监护</span></div>
    </section>
    <HudFrame tag="section" class="login-card" aria-labelledby="login-heading">
      <div class="login-card-caption"><AppIcon name="Lock" :size="20" /><span>账号登录 / SIGN IN</span></div>
      <h2 id="login-heading">工作账号登录</h2>
      <el-form ref="formRef" :model="form" :rules="rules" label-position="top" size="large" :disabled="submitting" @submit.prevent="submit">
        <el-form-item label="账号" prop="username"><el-input v-model="form.username" name="username" autocomplete="username" placeholder="请输入工作账号"><template #prefix><AppIcon name="User" /></template></el-input></el-form-item>
        <el-form-item label="密码" prop="password"><el-input v-model="form.password" name="password" :type="passwordVisible ? 'text' : 'password'" autocomplete="current-password" placeholder="请输入密码"><template #prefix><AppIcon name="Lock" /></template><template #suffix><button type="button" class="password-toggle" :aria-label="passwordVisible ? '隐藏密码' : '显示密码'" :aria-pressed="passwordVisible" :disabled="submitting" @click="passwordVisible = !passwordVisible"><AppIcon :name="passwordVisible ? 'View' : 'Hide'" :size="20" /></button></template></el-input></el-form-item>
        <el-form-item v-if="captchaEnabled" label="图形验证码" prop="code">
          <div class="captcha-row"><el-input v-model="form.code" name="captcha" autocomplete="off" placeholder="请输入验证码"><template #prefix><AppIcon name="Checked" /></template></el-input><button type="button" class="captcha-image" :disabled="captchaLoading || submitting" aria-label="刷新验证码图片" @click="refreshCaptcha"><img v-if="captchaImage" :src="captchaImage" alt="图形验证码" @error="captchaImageFailed" /><span v-else>待刷新</span></button><button type="button" class="icon-button captcha-refresh" aria-label="刷新验证码" :disabled="captchaLoading || submitting" @click="refreshCaptcha"><AppIcon name="Refresh" /></button></div>
        </el-form-item>
        <p v-if="captchaLoading" class="form-hint" role="status">正在获取登录配置…</p>
        <div v-if="captchaError" class="form-error" role="alert"><span>{{ captchaError }}</span><button type="button" class="text-button" :disabled="captchaLoading" @click="refreshCaptcha">重新获取</button></div>
        <p v-if="errorMessage" ref="errorRef" class="form-error" role="alert" tabindex="-1">{{ errorMessage }}</p>
        <el-button class="login-submit" type="primary" native-type="submit" :loading="submitting" :disabled="!captchaReady || captchaLoading">{{ submitting ? '正在登录…' : '登录' }}</el-button>
      </el-form>
      <p class="login-note">请使用工作账号登录</p>
    </HudFrame>
    <footer class="login-footer"><p>为电力行业现场作业安全保驾护航</p><span>更安全 · 更高效 · 更可持续</span><small>背景为概念视觉，不代表真实现场</small></footer>
  </main>
</template>
