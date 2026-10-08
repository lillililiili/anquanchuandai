<script setup>
import { ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import { session } from "@/stores/session";
import { go } from "@/lib/actions";
import { saveAuth } from "@/lib/auth";
import { db, refreshSnapshot } from "@/mock/runtime";

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
    const body = await response.json();
    saveAuth(body.token, account.value);
    if (!await refreshSnapshot()) throw Error("业务数据读取失败");
    if (!db.state.stations.some(site => site.id === session.station)) session.station = db.state.stations[0]?.id || "";
    session.formDrafts = {};
  } catch {
    error.value = "后端未连接，修改未保存";
    return;
  }
  go("overview");
}
</script>

<template>
  <div class="login-page">
    <div class="login-logo rl-brand rl-brand-light" role="img" aria-label="融瓴 ROLLING"><img class="rl-brand-mark" src="/assets/brand-mark.svg" alt="" width="42" height="42" /><span class="rl-brand-type" aria-hidden="true"><b class="rl-brand-name">融瓴</b><span class="rl-brand-en">ROLLING</span></span></div>
    <div class="login-copy">
      <h1>智能穿戴安全监护平台</h1>
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
