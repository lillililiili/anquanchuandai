<script setup>
import { computed } from "vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTag from "@/components/ui/AppTag.vue";
import { typeNames } from "@/mock/data";
import { db, tick } from "@/mock/runtime";
import { deviceStatus, deviceStatusTone, projectDevice } from "@/lib/device-telemetry";
import { isSimulatedWatch } from "@/lib/sample-data";
import { formatBeijingDateTime } from "@/lib/date-time";
import { featureState } from '../../../../shared/device-features.mjs';

const props = defineProps({
  personId: { type: String, required: true },
  large: Boolean,
});

const images = { H: "helmet", B: "harness", W: "watch" };

const devices = computed(() => {
  tick.value;
  return db.currentDevices(props.personId).filter(device => device.active !== false).map(device => projectDevice(device));
});

function deviceOf(type) {
  return devices.value.find((item) => item.type === type);
}
const visibleTypes = computed(() => { tick.value; return db.state.businessConfig?.simulatedWatchVisible === false ? ['H', 'B'] : ['H', 'B', 'W']; });

function tone(device) {
  if (featureState(device, 'battery').verified && deviceStatus(device) === "在线" && device.battery != null && device.battery <= 20) return "yellow";
  return deviceStatusTone(device);
}

function label(device) {
  if (isSimulatedWatch(device)) return '模拟数据';
  if (featureState(device, 'battery').verified && deviceStatus(device) === "在线" && device.battery != null && device.battery <= 20) return "电量 " + device.battery + "%";
  return deviceStatus(device);
}
function statusValue(device, key, value) {
  const feature = featureState(device, key);
  if (!feature.verified) return '待联调';
  return value == null ? '暂无有效上报' : value;
}
function reportTime(device) {
  if (!device.updated) return isSimulatedWatch(device) ? '暂无示例时间' : '暂无真实上报';
  const formatted = formatBeijingDateTime(device.updated);
  return formatted === '—' ? '时间格式无效' : formatted;
}
const hooks = value => value === true ? '已挂接' : value === false ? '未挂接' : null;
</script>

<template>
  <div :class="['device-strip', large ? 'large' : '']">
    <div v-for="type in visibleTypes" :key="type" class="device-item">
      <img v-if="deviceOf(type)" :src="'/assets/' + images[type] + '.png?v=transparent-20260921'" :alt="typeNames[type]" />
      <AppIcon v-else name="link-unlink" />
      <div v-if="large" class="device-summary">
        <div class="device-summary-head">
          <b>{{ typeNames[type] }}</b>
          <AppStatus v-if="deviceOf(type)" :color="tone(deviceOf(type))">{{ label(deviceOf(type)) }}</AppStatus>
          <AppTag v-else color="muted">未领用</AppTag>
        </div>
        <small class="device-summary-id">设备编号：{{ deviceOf(type)?.id || "未领用" }}</small>
        <div v-if="deviceOf(type)" class="device-facts">
          <div class="device-fact device-fact-wide">
            <span>{{ isSimulatedWatch(deviceOf(type)) ? '示例时间' : '末次上报' }}</span>
            <strong>{{ reportTime(deviceOf(type)) }}</strong>
          </div>
          <div v-if="featureState(deviceOf(type), 'battery').supported" class="device-fact">
            <span>电量</span>
            <strong>{{ statusValue(deviceOf(type), 'battery', deviceOf(type).battery == null ? null : deviceOf(type).battery + '%') }}</strong>
          </div>
          <div v-if="featureState(deviceOf(type), 'wear').supported" class="device-fact">
            <span>佩戴状态</span>
            <strong>{{ statusValue(deviceOf(type), 'wear', deviceOf(type).worn === true ? '已佩戴' : deviceOf(type).worn === false ? '未佩戴' : null) }}</strong>
          </div>
          <div v-if="featureState(deviceOf(type), 'hooks').supported" class="device-fact device-fact-wide">
            <span>双钩状态</span>
            <strong>{{ statusValue(deviceOf(type), 'hooks', hooks(deviceOf(type).hookAEngaged)) }} / {{ statusValue(deviceOf(type), 'hooks', hooks(deviceOf(type).hookBEngaged)) }}</strong>
          </div>
          <div v-if="featureState(deviceOf(type), 'height').supported" class="device-fact">
            <span>相对高度</span>
            <strong>{{ statusValue(deviceOf(type), 'height', (deviceOf(type).relativeHeight ?? deviceOf(type).height) == null ? null : (deviceOf(type).relativeHeight ?? deviceOf(type).height) + ' m') }}</strong>
          </div>
        </div>
      </div>
      <div v-else>
        <b v-if="large">{{ typeNames[type] }}</b>
        <small>{{ deviceOf(type)?.id || "未领用" }}</small>
        <AppStatus v-if="deviceOf(type)" :color="tone(deviceOf(type))">{{ label(deviceOf(type)) }}</AppStatus>
        <AppTag v-else color="muted">未领用</AppTag>
      </div>
    </div>
  </div>
</template>
