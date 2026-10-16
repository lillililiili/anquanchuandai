<script setup>
import { computed, ref } from 'vue';
import AppTable from '../../src/components/ui/AppTable.vue';
import AppButton from '../../src/components/ui/AppButton.vue';
const all=Array.from({length:25}, (_,index)=>({id:index+1,name:`测试记录 ${index+1}`}));
const filter=ref('全部'), selected=ref('未选择');
const rows=computed(()=>filter.value==='空数据'?[]:filter.value==='少量'?all.slice(0,3):all);
</script>
<template>
  <main class="main" style="padding:24px; max-width:1200px; margin:auto">
    <h1>表格分页验收（隔离数据）</h1>
    <div class="row" style="margin:16px 0">
      <AppButton @click="filter='全部'">全部记录</AppButton>
      <AppButton @click="filter='少量'">筛选三条</AppButton>
      <AppButton @click="filter='空数据'">空数据</AppButton>
      <span>当前选择：{{ selected }}</span>
    </div>
    <AppTable v-slot="{rows:pageRows,offset}" :rows="rows" :reset-key="filter" :columns="['序号','记录','操作']" style="max-height:320px">
      <tr v-for="(row,index) in pageRows" :key="row.id" style="height:60px"><td>{{offset+index+1}}</td><td>{{row.name}}</td><td><AppButton @click="selected=row.name">选择 {{row.id}}</AppButton></td></tr>
    </AppTable>
    <section style="width:310px; margin-top:24px" aria-label="窄栏独立表格">
      <AppTable v-slot="{rows:pageRows}" :rows="all" :columns="['记录']" style="max-height:240px"><tr v-for="row in pageRows" :key="row.id"><td>{{row.name}}</td></tr></AppTable>
    </section>
  </main>
</template>
