<script setup>
import { computed } from "vue";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";

const profile = computed(() => {
  tick.value;
  const operator = db.state.operator || {};
  const names = { system: "系统管理员", site: "厂站管理员", asset: "资产管理员", duty: "平台值守员", audit: "审计员", "mobile-user": "普通用户（本人业务）" };
  return { loginName: operator.loginName || "身份暂未获取", roleName: (operator.roleIds || []).map(id => names[id] || id).join("、") || "角色暂未获取" };
});
const stationName = computed(() => {
  tick.value;
  return db.state.stations.find((item) => item.id === session.station)?.name;
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
