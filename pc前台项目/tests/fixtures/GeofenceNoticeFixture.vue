<script setup>
import { ref } from 'vue';
import GeofenceNoticePanel from '../../src/components/layout/GeofenceNoticePanel.vue';
import { createGeofenceNoticeTracker } from '../../src/lib/geofence-notices';
const tracker = createGeofenceNoticeTracker(), notices = ref([]), all = ref([]), opened = ref('');
const refresh = () => { notices.value = tracker.update({ accountId: 'fixture', station: 'fixture-site', online: true, events: all.value }); };
refresh();
function add(direction) {
  const n = all.value.length + 1;
  all.value.unshift({ id: 'fixture-' + n, station: 'fixture-site', source: 'PLATFORM_GEOFENCE', type: '电子围栏', status: '待认领',
    snapshot: { personName: '测试人员' }, fenceName: '设备检修区', fenceDirection: direction, date: '2026-11-09', time: '17:30:' + String(n).padStart(2, '0'),
    occurredAt: '2026-11-09T09:30:' + String(n).padStart(2, '0') + 'Z' });
  refresh();
}
</script>
<template>
  <main>
    <p class="eyebrow">隔离验收 · 示例数据</p><h1>电子围栏进出提醒</h1>
    <p>以下操作仅演示提醒效果，不向业务服务器写入数据。</p>
    <div class="actions"><button @click="add('进入')">模拟进入</button><button @click="add('离开')">模拟离开</button><button @click="refresh">重复同步</button></div>
    <p v-if="opened" role="status">{{ opened }}</p>
    <section><h2>进出记录</h2><p v-if="!all.length">点击上方按钮验证提醒。</p><p v-for="item in all" :key="item.id">{{ item.time }}　测试人员　{{ item.fenceDirection }}设备检修区</p></section>
  </main>
  <GeofenceNoticePanel :notices="notices" @dismiss="notices = tracker.dismiss($event)" @dismiss-all="notices = tracker.dismissAll()"
    @open="item => { opened = '已打开告警：' + item.fenceDirection + item.fenceName; notices = tracker.dismiss(item.id); }" @open-all="opened = '已打开全部围栏告警'" />
</template>
<style>
* { box-sizing: border-box; } body { margin: 0; background: radial-gradient(ellipse at 70% 10%, #153b54, #081c2b 70%); color: #e7f4ff; min-height: 100vh; font: 15px/1.6 'Microsoft YaHei', sans-serif; }
main { max-width: 940px; margin: 0 auto; padding: 60px 28px; } .eyebrow { color: #9bb7ca; letter-spacing: 1px; font-size: 13px; } h1 { margin: 8px 0 16px; font-size: 30px; } main > p { color: #b5cfdf; }
.actions { display: flex; flex-wrap: wrap; gap: 12px; margin: 28px 0; } .actions button { background: #174c69; border: 1px solid #489ec7; border-radius: 5px; padding: 10px 20px; color: #e7f4ff; font: inherit; cursor: pointer; } .actions button:hover { background: #216484; }
section { padding: 24px; background: #12324999; border: 1px solid #2c536c; border-radius: 8px; } h2 { margin: 0 0 20px; font-size: 18px; } section p { color: #b5cfdf; }
</style>
