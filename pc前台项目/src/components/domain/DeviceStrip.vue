<script setup>
import { computed } from "vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { typeNames } from "@/mock/data";
import { db, tick } from "@/mock/runtime";

const props = defineProps({
  personId: { type: String, required: true },
  large: Boolean,
});

const images = { H: "helmet", B: "harness", W: "watch" };

const devices = computed(() => {
  tick.value;
  return db.currentDevices(props.personId);
});

function deviceOf(type) {
  return devices.value.find((item) => item.type === type);
}

function tone(device) {
  if (!device.online) return "red";
  if (device.battery <= 20) return "yellow";
  return "green";
}

function label(device) {
  if (!device.online) return "连接中断";
  if (device.battery <= 20) return "电量 " + device.battery + "%";
  return "在线";
}
</script>

<template>
  <div :class="['device-strip', large ? 'large' : '']">
    <div v-for="type in ['H', 'B', 'W']" :key="type" class="device-item">
      <img v-if="deviceOf(type)" :src="'/assets/' + images[type] + '.png?v=transparent-20260921'" :alt="typeNames[type]" />
      <AppIcon v-else name="link-unlink" />
      <div>
        <b v-if="large">{{ typeNames[type] }}</b>
        <small>{{ deviceOf(type)?.id || "未领用" }}</small>
        <AppStatus v-if="deviceOf(type)" :color="tone(deviceOf(type))">{{ label(deviceOf(type)) }}</AppStatus>
        <AppTag v-else color="muted">未领用</AppTag>
        <template v-if="large && deviceOf(type)">
          <small>末次上报<br />{{ deviceOf(type).updated }}</small>
          <small><AppIcon name="battery-line" /> 电量 {{ deviceOf(type).battery }}%</small>
        </template>
      </div>
    </div>
  </div>
</template>
