<template>
  <main class="login-page">
    <section class="login-visual" aria-label="工业安全监控场景">
      <div class="visual-content">
        <div class="brand-lockup">
          <span class="brand-mark"><img :src="appLogo" alt="分体式智能安全帽平台" /></span>
          <span class="brand-name">分体式智能安全帽平台</span>
        </div>
        <div class="visual-copy">
          <p class="visual-kicker">FIELD DISPATCH</p>
          <h1>矿区作业调度台<br />安全帽在线值守</h1>
          <p class="visual-description">
            集中掌握设备、人员、告警与现场音视频，帮助值班人员快速判断并稳妥响应。
          </p>
        </div>
        <div class="visual-meta">
          <span>实时状态</span>
          <span>应急响应</span>
          <span>协同调度</span>
        </div>
      </div>
    </section>

    <section class="login-panel">
      <div class="mobile-brand">
        <span class="brand-mark"><img :src="appLogo" alt="分体式智能安全帽平台" /></span>
        <span class="brand-name">分体式智能安全帽平台</span>
      </div>

      <el-form
        ref="loginRef"
        class="login-form"
        :model="loginForm"
        :rules="loginRules"
      >
        <header class="login-header">
          <p class="login-eyebrow">分体式智能安全帽平台</p>
          <h2>进入调度台</h2>
          <p>使用值班账号登录，查看设备、人员与告警。</p>
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
import appLogo from '@/assets/logo/app-logo.png'

const userStore = useUserStore()
const router = useRouter()
const { proxy } = getCurrentInstance()

const loginForm = ref({
  username: '',
  password: '',
  code: '',
  uuid: ''
})

const loginRules = {
  username: [{ required: true, trigger: 'blur', message: '请输入您的账号' }],
  password: [{ required: true, trigger: 'blur', message: '请输入您的密码' }],
  code: [{ required: true, trigger: 'change', message: '请输入验证码' }]
}

const codeUrl = ref('')
const loading = ref(false)
const captchaEnabled = ref(true)

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
.login-page {
  display: grid;
  grid-template-columns: minmax(0, 52%) minmax(440px, 48%);
  min-height: 100%;
  overflow: hidden;
  background: #f3f4f6;
}

.login-visual {
  position: relative;
  min-height: 100vh;
  overflow: hidden;
  color: #f7f4ec;
  background:
    linear-gradient(180deg, rgba(42, 46, 41, 0.18), rgba(42, 46, 41, 0.55)),
    url('../assets/images/login-industrial-v2.webp') center center / cover no-repeat,
    #2a2e29;

  &::before {
    content: '';
    position: absolute;
    top: 0;
    bottom: 0;
    left: 0;
    width: 6px;
    background: #b45309;
  }

  &::after {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(180deg, rgba(42, 46, 41, 0.12) 0%, rgba(30, 34, 28, 0.62) 100%);
    pointer-events: none;
  }
}

.visual-content {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  min-height: 100%;
  padding: clamp(28px, 3.2vw, 54px);
}

.brand-lockup,
.mobile-brand {
  display: flex;
  align-items: center;
  gap: 12px;
}

.brand-mark {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  overflow: hidden;
  border: 0;
  border-radius: 8px;
  background: transparent;
  box-shadow: none;

  img {
    width: 40px;
    height: 40px;
    display: block;
    object-fit: cover;
  }
}

.brand-name {
  font-size: 15px;
  font-weight: 620;
  letter-spacing: 0.01em;
}

.visual-copy {
  width: min(620px, 80%);
  margin-top: auto;
  margin-bottom: 58px;
  padding: 28px 0 0;
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
}

.visual-kicker {
  margin: 0 0 14px;
  color: #f0c48a;
  font-family: var(--font-mono);
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.16em;
}

.visual-copy h1 {
  margin: 0;
  color: #fff;
  font-size: clamp(28px, 2.5vw, 44px);
  font-weight: 620;
  line-height: 1.28;
  letter-spacing: -0.02em;
}

.visual-description {
  max-width: 560px;
  margin: 18px 0 0;
  color: rgba(236, 241, 247, 0.76);
  font-size: 14px;
  line-height: 1.75;
}

.visual-meta {
  display: flex;
  gap: 24px;
  color: rgba(255, 255, 255, 0.68);
  font-size: 12px;

  span + span {
    position: relative;

    &::before {
      content: '';
      position: absolute;
      top: 50%;
      left: -13px;
      width: 1px;
      height: 12px;
      background: rgba(255, 255, 255, 0.26);
      transform: translateY(-50%);
    }
  }
}

.login-panel {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  padding: 48px clamp(38px, 5vw, 84px);
  color: var(--text-primary);
  background: var(--bg-base);
}

.mobile-brand {
  display: none;
}

.login-form {
  width: min(100%, 420px);
}

.login-header {
  margin-bottom: 34px;
}

.login-eyebrow {
  margin: 0 0 8px;
  color: var(--color-primary);
  font-size: 13px;
  font-weight: 650;
}

.login-header h2 {
  margin: 0;
  color: var(--text-primary);
  font-size: 30px;
  font-weight: 650;
  line-height: 1.3;
  letter-spacing: -0.02em;
}

.login-header > p:last-child {
  margin: 10px 0 0;
  color: var(--text-secondary);
  font-size: 14px;
}

.field-label {
  display: block;
  width: 100%;
  margin-bottom: 8px;
  color: var(--text-primary);
  font-size: 13px;
  font-weight: 600;
}

.login-form :deep(.el-form-item) {
  display: block;
  margin-bottom: 20px;
}

.login-form :deep(.el-form-item__content) {
  display: block;
  line-height: normal;
}

.login-form :deep(.el-input__wrapper) {
  min-height: 48px;
  padding-inline: 14px;
  border-radius: 4px;
  background: var(--bg-pure);
}

.input-icon {
  width: 16px;
  height: 16px;
  color: var(--text-muted);
}

.captcha-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 126px;
  gap: 10px;
}

.login-code {
  height: 48px;
  padding: 0;
  overflow: hidden;
  border: 1px solid var(--border-color);
  border-radius: 4px;
  background: #fff;
  cursor: pointer;
}

.login-code-img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.submit-item {
  margin-top: 28px;
}

.login-button {
  width: 100%;
  min-height: 48px;
  border-radius: 4px;
  font-size: 15px;
  font-weight: 620;
}

.login-support {
  margin: 30px 0 0;
  color: var(--text-muted);
  font-size: 12px;
  text-align: center;
}

@media (max-width: 1180px) {
  .login-page {
    grid-template-columns: minmax(0, 50%) minmax(420px, 50%);
  }

  .visual-copy {
    width: 92%;
  }
}

@media (max-width: 820px) {
  .login-page {
    display: block;
    min-height: 100%;
    overflow-y: auto;
    background: var(--bg-base);
  }

  .login-visual {
    display: none;
  }

  .login-panel {
    min-height: 100vh;
    padding: 32px 22px;
  }

  .mobile-brand {
    display: flex;
    position: absolute;
    top: 24px;
    left: 24px;

    .brand-mark {
      background: transparent;
    }
  }

  .login-form {
    padding-top: 72px;
  }
}

@media (max-width: 480px) {
  .captcha-row {
    grid-template-columns: minmax(0, 1fr) 108px;
  }

  .login-header h2 {
    font-size: 26px;
  }
}
</style>
