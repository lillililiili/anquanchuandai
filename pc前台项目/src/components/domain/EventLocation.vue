<script setup>
import { computed } from "vue";
import PlantMap from "./PlantMap.vue";
import { eventLocation, mapLocation, validLonLat } from "@/lib/location";
const props = defineProps({ event: { type: Object, required: true } });
const position = computed(() => eventLocation(props.event));
const valid = computed(() => Boolean(mapLocation(position.value)));
const hasCoordinates = computed(() => validLonLat(position.value.longitude, position.value.latitude));
</script>
<template>
  <div class="event-location">
    <PlantMap v-if="valid" :location="position" :markers="false" :fences="false" :legend="false" />
    <p v-else class="note">{{ hasCoordinates ? '收到坐标，但坐标系或定位质量尚未核实，暂不绘制位置。' : '本事件没有有效位置快照，可补充现场说明。' }}</p>
    <p v-if="hasCoordinates">经度 {{ Number(position.longitude).toFixed(6) }} · 纬度 {{ Number(position.latitude).toFixed(6) }} · {{ position.coordinateSystem || '坐标系待核实' }}</p>
    <small class="muted">显示事件发生时保存的位置；后续人员移动不会改变此记录。</small>
  </div>
</template>
<style scoped>.event-location .map{height:280px;min-height:280px}.event-location p{overflow-wrap:anywhere}</style>
