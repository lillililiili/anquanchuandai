<script setup>
import { computed } from "vue";
import { useRoute } from "vue-router";
import AppIcon from "@/components/ui/AppIcon.vue";

const route = useRoute();
const items = [
  ["overview", "综合总览", "layout-grid-line"],
  ["personnel", "人员与装备", "user-line"],
  ["works", "作业监护", "clipboard-line"],
  ["video", "视频监看", "vidicon-line"],
  ["dispatch", "调度通信", "mic-line"],
  ["location", "定位与轨迹", "map-pin-line"],
  ["alarms", "告警与核验", "alarm-warning-line"],
  ["materials", "现场资料", "file-list-3-line"],
  ["statistics", "统计追溯", "bar-chart-box-line"],
];
const ownerOf = {
  person: "personnel",
  work: "works",
  single: "video",
  tracks: "location",
  fences: "location",
  event: "alarms",
  sos: "dispatch",
};
const active = computed(() => ownerOf[route.name] || route.name);
</script>

<template>
  <aside class="sidebar">
    <nav>
      <a v-for="[id, label, icon] in items" :key="id" :href="'#/' + id" :class="active === id ? 'active' : ''">
        <AppIcon :name="icon" />
        <span>{{ label }}</span>
      </a>
    </nav>
    <div class="sidebar-bottom"><small>示例数据</small></div>
  </aside>
</template>
