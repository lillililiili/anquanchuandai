<script setup>
import App from '../../src/App.vue';
import { scenario, selectScenario, SCENARIOS, blockedOperations } from './person-device-runtime.js';
import { useRouter } from 'vue-router';
const router = useRouter();
const pages = [ ['personnel','人员与装备'], ['person/QA-PERSON','人员详情'], ['work/QA-WORK','作业详情'], ['video','视频监看'], ['single/QA-PERSON','单路监看'], ['dispatch?personId=QA-PERSON','调度通信'], ['event/QA-SOS','事件详情'], ['sos?eventId=QA-SOS','SOS 处置'] ];
</script>
<template>
  <App />
  <details class="fixture-controls" open>
    <summary>隔离页面验收 · 所有数据为测试夹具 · 无外部连接</summary>
    <div><label>场景 <select :value="scenario" @change="selectScenario($event.target.value)"><option v-for="[id,label] in SCENARIOS" :key="id" :value="id">{{ label }}</option></select></label>
      <button @click="selectScenario(scenario)">重置场景 / 刷新测试时间</button>
      <button v-for="[path,label] in pages" :key="path" @click="router.push('/' + path)">{{ label }}</button></div>
    <p>仅验收页面条件、布局及失败态；在线与能力来自夹具，不代表实机通过。外部地图底图、视频、语音、数据库均已隔离。切换场景不刷新页面，可检查权限撤销和领用失效。</p>
    <output v-if="blockedOperations.length">{{ blockedOperations.at(-1) }}</output>
  </details>
</template>
<style>
.fixture-controls{position:fixed;bottom:8px;left:8px;right:8px;z-index:20000;border:2px solid #ffd166;border-radius:5px;background:#17202deF;color:#fff;padding:8px 12px;font:13px/1.5 sans-serif;box-shadow:0 0 15px #0008}
.fixture-controls summary{cursor:pointer;font-weight:700;color:#ffd166}.fixture-controls>div{display:flex;gap:7px;flex-wrap:wrap;margin:8px 0}.fixture-controls select,.fixture-controls button{font:inherit;color:#fff;background:#243e56;border:1px solid #5b7996;border-radius:3px;padding:4px 7px;cursor:pointer}.fixture-controls p{margin:3px 0}.fixture-controls output{color:#ffd166}
</style>
