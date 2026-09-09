<template>
  <div class="register">
    <el-form
      ref="registerRef"
      class="register-form"
      :model="registerForm"
      :rules="registerRules"
    >
      <h3 class="title">创建平台账号</h3>
      <el-form-item prop="username">
        <el-input
          v-model="registerForm.username"
          auto-complete="off"
          placeholder="账号"
          size="large"
          type="text"
        >
          <template #prefix
            ><svg-icon class="el-input__icon input-icon" icon-class="user"
          /></template>
        </el-input>
      </el-form-item>
      <el-form-item prop="password">
        <el-input
          v-model="registerForm.password"
          auto-complete="off"
          placeholder="密码"
          size="large"
          type="password"
          @keyup.enter="handleRegister"
        >
          <template #prefix
            ><svg-icon class="el-input__icon input-icon" icon-class="password"
          /></template>
        </el-input>
      </el-form-item>
      <el-form-item prop="confirmPassword">
        <el-input
          v-model="registerForm.confirmPassword"
          auto-complete="off"
          placeholder="确认密码"
          size="large"
          type="password"
          @keyup.enter="handleRegister"
        >
          <template #prefix
            ><svg-icon class="el-input__icon input-icon" icon-class="password"
          /></template>
        </el-input>
      </el-form-item>
      <el-form-item v-if="captchaEnabled" prop="code">
        <el-input
          v-model="registerForm.code"
          auto-complete="off"
          placeholder="验证码"
          size="large"
          style="width: 63%"
          @keyup.enter="handleRegister"
        >
          <template #prefix
            ><svg-icon class="el-input__icon input-icon" icon-class="validCode"
          /></template>
        </el-input>
        <div class="register-code">
          <img class="register-code-img" :src="codeUrl" @click="getCode" />
        </div>
      </el-form-item>
      <el-form-item style="width: 100%">
        <el-button
          :loading="loading"
          size="large"
          style="width: 100%"
          type="primary"
          @click.prevent="handleRegister"
        >
          <span v-if="!loading">注 册</span>
          <span v-else>注 册 中...</span>
        </el-button>
        <div style="float: right">
          <router-link class="link-type" :to="'/login'"
            >使用已有账户登录</router-link
          >
        </div>
      </el-form-item>
    </el-form>
    <!--  底部  -->
    <div class="el-register-footer">
      <span>智能穿戴管理平台 · 安全运营系统</span>
    </div>
  </div>
</template>

<script setup>
import { ElMessageBox } from 'element-plus'
import { getCodeImg, register } from '@/api/login'

const router = useRouter()
const { proxy } = getCurrentInstance()

const registerForm = ref({
  username: '',
  password: '',
  confirmPassword: '',
  code: '',
  uuid: '',
})

const equalToPassword = (rule, value, callback) => {
  if (registerForm.value.password !== value) {
    callback(new Error('两次输入的密码不一致'))
  } else {
    callback()
  }
}

const registerRules = {
  username: [
    { required: true, trigger: 'blur', message: '请输入您的账号' },
    {
      min: 2,
      max: 20,
      message: '用户账号长度必须介于 2 和 20 之间',
      trigger: 'blur',
    },
  ],
  password: [
    { required: true, trigger: 'blur', message: '请输入您的密码' },
    {
      min: 5,
      max: 20,
      message: '用户密码长度必须介于 5 和 20 之间',
      trigger: 'blur',
    },
  ],
  confirmPassword: [
    { required: true, trigger: 'blur', message: '请再次输入您的密码' },
    { required: true, validator: equalToPassword, trigger: 'blur' },
  ],
  code: [{ required: true, trigger: 'change', message: '请输入验证码' }],
}

const codeUrl = ref('')
const loading = ref(false)
const captchaEnabled = ref(true)

function handleRegister() {
  proxy.$refs.registerRef.validate((valid) => {
    if (valid) {
      loading.value = true
      register(registerForm.value)
        .then((res) => {
          const username = registerForm.value.username
          ElMessageBox.alert(
            "<font color='red'>恭喜你，您的账号 " +
              username +
              ' 注册成功！</font>',
            '系统提示',
            {
              dangerouslyUseHTMLString: true,
              type: 'success',
            }
          )
            .then(() => {
              router.push('/login')
            })
            .catch(() => {})
        })
        .catch(() => {
          loading.value = false
          if (captchaEnabled.value) {
            getCode()
          }
        })
    }
  })
}

function getCode() {
  getCodeImg().then((res) => {
    captchaEnabled.value =
      res.captchaEnabled === undefined ? true : res.captchaEnabled
    if (captchaEnabled.value) {
      codeUrl.value = 'data:image/gif;base64,' + res.img
      registerForm.value.uuid = res.uuid
    }
  })
}

getCode()
</script>

<style lang="scss" scoped>
.register {
  display: flex;
  justify-content: center;
  align-items: center;
  height: 100%;
  min-height: 100%;
  padding: 32px;
  background-color: rgba(10, 15, 22, 0.68);
  background-image: url('../assets/images/login-industrial-v2.webp');
  background-position: center;
  background-size: cover;
  background-blend-mode: multiply;
}
.title {
  margin: 0px auto 30px auto;
  text-align: center;
  color: var(--text-primary);
  font-size: 24px;
  font-weight: 650;
}

.register-form {
  width: min(100%, 440px);
  padding: 34px 36px 20px;
  border: 1px solid var(--border-color);
  border-radius: 12px;
  background: var(--bg-elevated);
  box-shadow: var(--shadow-xl);
  .el-input {
    height: 46px;
    input {
      height: 46px;
    }
  }
  .input-icon {
    height: 39px;
    width: 14px;
    margin-left: 0px;
  }
}
.register-tip {
  font-size: 13px;
  text-align: center;
  color: var(--text-muted);
}
.register-code {
  width: 33%;
  height: 46px;
  float: right;
  img {
    cursor: pointer;
    vertical-align: middle;
  }
}
.el-register-footer {
  height: 40px;
  line-height: 40px;
  position: fixed;
  bottom: 0;
  width: 100%;
  text-align: center;
  color: rgba(255, 255, 255, 0.72);
  font-family: var(--font-sans);
  font-size: 12px;
  letter-spacing: 1px;
}
.register-code-img {
  width: 100%;
  height: 46px;
  object-fit: cover;
  padding-left: 12px;
}

@media (max-width: 600px) {
  .register {
    padding: 18px;
  }

  .register-form {
    padding: 28px 22px 16px;
  }
}
</style>
