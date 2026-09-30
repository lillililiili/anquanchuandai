<script setup>
import { authFetch } from "@/lib/auth";
import { computed, onMounted, ref } from "vue";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";

const profile = ref({ loginName: "duty", roleName: "平台值守员" });
const stationName = computed(() => {
  tick.value;
  return db.state.stations.find((item) => item.id === session.station)?.name;
});

onMounted(async () => {
  try {
    const response = await authFetch("/api/guardian/v1/operator");
    if (!response.ok) return;
    const body = await response.json();
    if (body.loginName) profile.value.loginName = body.loginName;
    if (body.roleName) profile.value.roleName = body.roleName;
  } catch {
    /* 接口暂时不可用时保留台账里的值守账号文案。 */
  }
});
</script>

<template>
  <dl class="info">
    <dt>账号</dt>
    <dd>{{ profile.loginName }}</dd>
    <dt>角色</dt>
    <dd>{{ profile.roleName }}</dd>
    <dt>当前厂站</dt>
    <dd>{{ stationName }}</dd>
  </dl>
</template>
