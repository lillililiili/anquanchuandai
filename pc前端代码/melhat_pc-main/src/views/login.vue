<template>
  <main class="login-page">
    <section class="login-visual" aria-label="工业安全监控场景">
      <div class="visual-content">
        <div class="brand-lockup"><BrandLogo caption /></div>
        <div class="visual-copy">
          <p class="visual-kicker">智能感知 · 安全协同</p>
          <h1>每一份专注<br /><span>都有安全守护</span></h1>
          <p class="visual-description">
            连接设备、人员与现场，让每一次作业清晰可见，<br />让每一次响应及时抵达。
          </p>
        </div>
        <div class="visual-meta">
          <span><svg-icon icon-class="helmet" /> 设备感知</span>
          <span><svg-icon icon-class="sos" /> 安全预警</span>
          <span><svg-icon icon-class="walkie-talkie" /> 协同调度</span>
        </div>
      </div>
    </section>

    <section class="login-panel">
      <div class="mobile-brand"><BrandLogo caption /></div>

      <el-form
        ref="loginRef"
        class="login-form"
        :model="loginForm"
        :rules="loginRules"
        :validate-on-rule-change="false"
      >
        <header class="login-header">
          <p class="login-eyebrow">安全运营工作台</p>
          <h2>欢迎回来</h2>
          <p>登录您的账号，开始安全有序的一天。</p>
        </header>

        <el-form-item prop="username">
          <label class="field-label" for="login-username">账号</label>
          <el-input
            id="login-username"
            v-model="loginForm.username"
            autocomplete="username"
            placeholder="请输入账号"
            size="large"
            type="text"
          >
            <template #prefix>
              <svg-icon class="input-icon" icon-class="user" />
            </template>
          </el-input>
        </el-form-item>

        <el-form-item prop="password">
          <label class="field-label" for="login-password">密码</label>
          <el-input
            id="login-password"
            v-model="loginForm.password"
            autocomplete="current-password"
            placeholder="请输入密码"
            show-password
            size="large"
            type="password"
            @keyup.enter="handleLogin"
          >
            <template #prefix>
              <svg-icon class="input-icon" icon-class="password" />
            </template>
          </el-input>
        </el-form-item>

        <el-form-item v-if="captchaEnabled" class="captcha-item" prop="code">
          <label class="field-label" for="login-code">验证码</label>
          <div class="captcha-row">
            <el-input
              id="login-code"
              v-model="loginForm.code"
              autocomplete="off"
              placeholder="请输入验证码"
              size="large"
              @keyup.enter="handleLogin"
            >
              <template #prefix>
                <svg-icon class="input-icon" icon-class="validCode" />
              </template>
            </el-input>
            <button class="login-code" type="button" title="刷新验证码" @click="getCode">
              <img class="login-code-img" :src="codeUrl" alt="验证码，点击刷新" />
            </button>
          </div>
        </el-form-item>

        <el-form-item class="submit-item">
          <el-button
            class="login-button"
            :loading="loading"
            size="large"
            type="primary"
            @click.prevent="handleLogin"
          >
            {{ loading ? '正在登录…' : '登录系统' }}
          </el-button>
        </el-form-item>

        <p class="login-support">安全运营平台 · 请使用授权账号访问</p>
      </el-form>
    </section>
  </main>
</template>

<script setup>
import { getCodeImg } from '@/api/login'
import useUserStore from '@/store/modules/user'

const userStore = useUserStore()
const router = useRouter()
const { proxy } = getCurrentInstance()

const loginForm = ref({
  username: '',
  password: '',
  code: '',
  uuid: ''
})

const codeUrl = ref('')
const loading = ref(false)
const captchaEnabled = ref(true)

const loginRules = computed(() => {
  const rules = {
    username: [{ required: true, trigger: 'blur', message: '请输入您的账号' }],
    password: [{ required: true, trigger: 'blur', message: '请输入您的密码' }]
  }
  if (captchaEnabled.value) {
    rules.code = [{ required: true, trigger: 'change', message: '请输入验证码' }]
  }
  return rules
})

function handleLogin() {
  proxy.$refs.loginRef.validate((valid) => {
    if (valid) {
      loading.value = true
      userStore
        .login(loginForm.value)
        .then(() => {
          router.push({ path: '/' })
        })
        .catch(() => {
          loading.value = false
          if (captchaEnabled.value) getCode()
        })
    }
  })
}

function getCode() {
  getCodeImg().then((res) => {
    captchaEnabled.value = res.captchaEnabled === undefined ? true : res.captchaEnabled
    if (captchaEnabled.value) {
      codeUrl.value = 'data:image/gif;base64,' + res.img
      loginForm.value.uuid = res.uuid
    }
  })
}

getCode()
</script>

<style lang="scss" scoped>
.login-page { display: grid; grid-template-columns: minmax(0, 58%) minmax(420px, 42%); height: 100dvh; min-height: 620px; background: #f4f7fa; overflow-y: auto; }
.login-visual { position: relative; min-height: 100%; overflow: hidden; background: #eaf0f6 url('/visuals/login-hero.webp') right center / cover no-repeat; }
.visual-content { position: relative; display: flex; flex-direction: column; min-height: 100%; padding: 40px clamp(32px, 4.2vw, 80px); }
.brand-lockup { display: flex; align-items: center; }
.brand-lockup :deep(.brand-logo__name) { font-size: 17px; }
.brand-lockup :deep(.brand-logo img) { width: 44px; height: 48px; }
.visual-copy { margin-top: clamp(48px, 9vh, 108px); max-width: 580px; }
.visual-kicker { margin: 0 0 20px; color: #1765d1; font-size: 13px; letter-spacing: 4px; font-weight: 600; }
.visual-copy h1 { margin: 0; color: #172b45; font-size: clamp(34px, 3.3vw, 58px); font-weight: 600; line-height: 1.35; letter-spacing: 1px; }
.visual-copy h1 span { color: #1765d1; }
.visual-description { margin: 22px 0 0; color: #52647a; font-size: 14px; line-height: 1.9; }
.visual-meta { display: flex; flex-wrap: wrap; align-items: center; gap: 24px; margin-top: auto; padding-top: 50px; color: #253e57; font-size: 12px; }
.visual-meta span { display: flex; align-items: center; gap: 7px; padding: 10px 12px; border: 1px solid rgba(255,255,255,.8); border-radius: 8px; background: rgba(255,255,255,.85); }
.visual-meta .svg-icon { color: #1765d1; width: 16px; height: 16px; }
.login-panel { display: flex; align-items: center; justify-content: center; min-height: 100%; padding: 36px clamp(28px, 3.4vw, 64px); background: #f7f9fc; border-left: 1px solid #e2e8f0; }
.mobile-brand { display: none; }
.login-form { width: 100%; max-width: 440px; padding: 42px 36px 30px; border: 1px solid #e2e8f0; border-radius: 20px; background: #fff; box-shadow: 0 16px 50px rgba(23,43,69,.055); }
.login-header { margin-bottom: 36px; }
.login-eyebrow { margin: 0 0 14px; font-size: 12px; font-weight: 500; letter-spacing: 2px; color: #148b98; }
.login-header h2 { margin: 0; font-size: 30px; font-weight: 600; color: #172b45; line-height: 1.35; }
.login-header > p:last-child { margin: 12px 0 0; font-size: 13px; line-height: 1.7; color: #6b7c90; }
.field-label { display: block; width: 100%; margin-bottom: 9px; color: #334b65; font-size: 13px; font-weight: 500; }
.login-form :deep(.el-form-item) { display: block; margin-bottom: 23px; }
.login-form :deep(.el-form-item__content) { display: block; line-height: normal; }
.login-form :deep(.el-input__wrapper) { min-height: 48px; padding-inline: 14px; border-radius: 8px; background: #f8fafc; }
.input-icon { width: 16px; height: 16px; color: #76869a; }
.captcha-row { display: grid; grid-template-columns: minmax(0, 1fr) 110px; gap: 10px; }
.login-code { height: 48px; padding: 0; overflow: hidden; border: 1px solid #e2e8f0; border-radius: 8px; background: #fff; cursor: pointer; }
.login-code-img { display: block; width: 100%; height: 100%; object-fit: contain; }
.submit-item { margin-top: 30px; }
.login-button { width: 100%; min-height: 48px; border-radius: 8px; font-size: 15px; font-weight: 500; box-shadow: 0 6px 16px rgba(23,101,209,.16); }
.login-support { margin: 30px 0 0; color: #6b7c90; font-size: 11px; text-align: center; line-height: 1.7; }
@media (max-width: 1180px) { .visual-content { padding: 32px; } .visual-meta { gap: 8px; } .login-panel { padding: 28px; } .login-form { padding: 36px 28px 26px; } }
@media (max-width: 820px) { .login-page { display: block; min-height: 100dvh; height: auto; } .login-visual { display: none; } .login-panel { flex-direction: column; align-items: stretch; justify-content: center; gap: 36px; min-height: 100dvh; padding: 32px 22px; border: 0; } .mobile-brand { display: flex; justify-content: center; } .login-form { align-self: center; padding: 30px 24px 24px; border-radius: 16px; } .login-header { margin-bottom: 28px; } .login-header h2 { font-size: 28px; } }
</style>
