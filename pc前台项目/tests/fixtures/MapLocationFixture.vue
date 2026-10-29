<script setup>
import { ref } from 'vue';
import PlantMap from '../../src/components/domain/PlantMap.vue';
import AreaRangeMap from '../../../pc后台项目/components/AreaRangeMap.vue';
const points = ref([]);
const coordinateSystem = ref('GCJ02');
</script>
<template>
  <main class="main" style="padding:20px;display:block;height:auto">
    <h2>固定测试厂区地图验收</h2>
    <div style="height:460px"><PlantMap /></div>
    <AreaRangeMap v-model="points" v-model:coordinate-system="coordinateSystem" />
    <p>保存坐标系：{{ coordinateSystem }}</p>
    <pre aria-label="绘制结果">{{ JSON.stringify(points) }}</pre>
  </main>
</template>
