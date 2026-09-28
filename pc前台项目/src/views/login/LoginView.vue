<script setup>
import { ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { session } from "@/stores/session";
import { go } from "@/lib/actions";

const account = ref("");
const password = ref("");
const error = ref("");

async function submit() {
  error.value = "";
  try {
    const response = await fetch("/api/guardian/v1/login", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({ account: account.value, password: password.value }),
    });
    if (!response.ok) {
      if (response.status >= 500) {
        error.value = "后端未连接，修改未保存";
        return;
      }
      let message = "账号或密码错误。";
      try {
        message = (await response.json()).message || message;
      } catch {
        /* 没有 JSON 正文时保留上面的默认文案。 */
      }
      error.value = message;
      return;
    }
  } catch {
    error.value = "后端未连接，修改未保存";
    return;
  }
  sessionStorage.setItem("rolling-session", account.value);
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
          <input v-model="password" name="password" :type="session.showPassword ? 'text' : 'password'" placeholder="请输入密码" autocomplete="current-password" required />
          <AppButton tone="icon-only plain" :icon="session.showPassword ? 'eye-line' : 'eye-off-line'" aria-label="显示或隐藏密码" @click="session.showPassword = !session.showPassword" />
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
  </div>
</template>
