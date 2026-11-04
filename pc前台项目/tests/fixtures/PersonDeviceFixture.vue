<script setup>
import App from '../../src/App.vue';
import { computed } from 'vue';
import { scenario, selectScenario, SCENARIOS, blockedOperations, memoryWrites, db, tick } from './person-device-runtime.js';
import { useRouter } from 'vue-router';
const router = useRouter();
const pages = [ ['personnel','人员与装备'], ['person/QA-PERSON','人员详情'], ['works','作业列表'], ['work/QA-WORK','作业详情'], ['fences','电子围栏'], ['video','视频监看'], ['single/QA-PERSON','单路监看'], ['dispatch?personId=QA-PERSON','调度通信'], ['event/QA-SOS','事件详情'], ['sos?eventId=QA-SOS','SOS 处置'] ];
const savedFences = computed(() => { tick.value; return db.state.fences.filter(fence => !fence.archived).map(fence => ({ name: fence.name, coordinateSystem: fence.coordinateSystem || '旧示意', enabled: fence.enabled, points: fence.points })); });
</script>
<template>
  <App />
  <details class="fixture-controls" open>
    <summary>隔离页面验收 · 所有数据为测试夹具 · 无外部连接</summary>
    <div><label>场景 <select :value="scenario" @change="selectScenario($event.target.value)"><option v-for="[id,label] in SCENARIOS" :key="id" :value="id">{{ label }}</option></select></label>
      <button @click="selectScenario(scenario)">重置场景 / 刷新测试时间</button>
      <button v-for="[path,label] in pages" :key="path" @click="router.push('/' + path)">{{ label }}</button></div>
    <p>在线与能力来自夹具，不代表实机通过。仅围栏场景允许当前页内存保存；刷新或重置后还原。外部地图底图、视频、语音、数据库均已隔离。地图网格只帮助点选，坐标仍由原地图组件转换。</p>
    <p v-if="scenario === 'works_many'">联系能力仅用于验证作业→调度通信跳转；实际发起通话仍被阻止。</p>
    <output v-if="memoryWrites.length">{{ memoryWrites.at(-1) }}</output>
    <details v-if="scenario === 'fences'"><summary>查看隔离内存中的已保存坐标</summary><pre data-testid="fixture-fence-state">{{ JSON.stringify(savedFences, null, 2) }}</pre></details>
    <output v-if="blockedOperations.length">{{ blockedOperations.at(-1) }}</output>
  </details>
</template>
<style>
.fixture-controls{position:fixed;bottom:8px;left:8px;right:8px;z-index:20000;border:2px solid #ffd166;border-radius:5px;background:#17202deF;color:#fff;padding:8px 12px;font:13px/1.5 sans-serif;box-shadow:0 0 15px #0008}
.fixture-controls summary{cursor:pointer;font-weight:700;color:#ffd166}.fixture-controls>div{display:flex;gap:7px;flex-wrap:wrap;margin:8px 0}.fixture-controls select,.fixture-controls button{font:inherit;color:#fff;background:#243e56;border:1px solid #5b7996;border-radius:3px;padding:4px 7px;cursor:pointer}.fixture-controls p{margin:3px 0}.fixture-controls output{color:#ffd166}
.fixture-controls pre{max-height:140px;overflow:auto;font:12px/1.4 monospace;white-space:pre-wrap}.map-ol{background-color:#18354b;background-image:linear-gradient(#6aa3bd22 1px,transparent 1px),linear-gradient(90deg,#6aa3bd22 1px,transparent 1px);background-size:32px 32px}
</style>
