<script setup>
import { ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { session } from "@/stores/session";
import { go } from "@/lib/actions";

const account = ref("");
const password = ref("");
const captcha = ref("");
const error = ref("");
session.captcha ||= "K7M2";

function refreshCaptcha() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  session.captcha = Array.from({ length: 4 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join("");
}

function submit() {
  error.value = "";
  if (account.value !== "admin" || password.value !== "123456") {
    error.value = "账号或密码错误。演示账号：admin / 123456";
    return;
  }
  if (captcha.value.toUpperCase() !== session.captcha) {
    error.value = "验证码错误，请重新输入";
    return;
  }
  sessionStorage.setItem("rolling-session", "admin");
  go("overview");
}
</script>

<template>
  <div class="login-page">
    <img class="login-logo" src="/assets/logo.png" alt="ROLLING" />
    <div class="login-copy">
      <h1>融瓴智能穿戴安全监护平台</h1>
      <p>现场人员 · 智能装备 · 作业监护</p>
    </div>
    <form class="login-card" @submit.prevent="submit">
      <h2>工作账号登录</h2>
      <label class="field">
        <span>账号</span>
        <div class="input-icon">
          <AppIcon name="user-line" />
          <input v-model="account" name="account" type="text" placeholder="请输入工作账号" autocomplete="username" required />
        </div>
      </label>
      <label class="field">
        <span>密码</span>
        <div class="input-icon">
          <AppIcon name="lock-line" />
          <input v-model="password" name="password" :type="session.showPassword ? 'text' : 'password'" autocomplete="current-password" required />
          <AppButton tone="icon-only plain" :icon="session.showPassword ? 'eye-line' : 'eye-off-line'" aria-label="显示或隐藏密码" @click="session.showPassword = !session.showPassword" />
        </div>
      </label>
      <label class="field">
        <span>图形验证码</span>
        <div class="captcha-row">
          <div class="input-icon">
            <AppIcon name="shield-check-line" />
            <input v-model="captcha" name="captcha" type="text" placeholder="请输入验证码" maxlength="4" autocomplete="off" required />
          </div>
          <span class="captcha-code" aria-label="验证码">{{ session.captcha }}</span>
          <AppButton icon="refresh-line" aria-label="刷新验证码" @click="refreshCaptcha" />
        </div>
      </label>
      <button class="btn primary" type="submit">登录</button>
      <small>账号由管理员授权</small>
      <div class="form-error" role="alert">{{ error }}</div>
    </form>
    <div class="login-footer">
      为电力行业现场作业安全保驾护航
      <small>更安全 · 更高效 · 更可持续</small>
    </div>
    <div class="login-help">演示账号：admin　密码：123456　｜　演示环境 · 非真实登录页</div>
  </div>
</template>
