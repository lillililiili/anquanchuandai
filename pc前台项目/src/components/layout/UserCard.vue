<script setup>
import { computed } from "vue";
import { db, tick } from "@/mock/runtime";
import { session } from "@/stores/session";

const stationName = computed(() => {
  tick.value;
  return db.state.stations.find((item) => item.id === session.station)?.name;
});
</script>

<template>
  <dl class="info">
    <dt>账号</dt>
    <dd>admin</dd>
    <dt>角色</dt>
    <dd>平台值守员</dd>
    <dt>当前厂站</dt>
    <dd>{{ stationName }}</dd>
    <dt>运行模式</dt>
    <dd>本地演示</dd>
  </dl>
</template>
