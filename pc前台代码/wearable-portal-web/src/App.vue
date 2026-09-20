<script setup>
import zhCn from 'element-plus/es/locale/lang/zh-cn'
const demo = import.meta.env.MODE === 'demo'
</script>

<template>
  <el-config-provider :locale="zhCn"><div v-if="demo" class="demo-environment" role="status">本地预置环境 · 独立数据库 · 不连接真实设备</div><router-view /></el-config-provider>
</template>
<style scoped>
.demo-environment { position: fixed; z-index: 3000; bottom: 0; left: 0; right: 0; height: 24px; line-height: 24px; text-align: center; background: #6a4000; color: #fff6d9; font-size: 12px; pointer-events: none; }
</style>
