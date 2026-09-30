<script setup>
import { ref } from 'vue'
import { getAdminProvider } from '@admin-provider'
import { useAdminStore } from '../store'
const store=useAdminStore(), provider=getAdminProvider(), busy=ref(false), message=ref(''), failed=ref(false)
const emit=defineEmits(['synced'])
async function sync() {
  if(busy.value)return
  const siteId=store.siteId
  busy.value=true;message.value='正在读取厂家设备，请稍候…';failed.value=false
  try {
    const response=await fetch('/api/admin/v1/platform/helmets/sync',{method:'POST',headers:{'Content-Type':'application/json','X-Wearable-Token':sessionStorage.getItem('wearable-admin-token')||''},body:JSON.stringify({siteId})})
    const result=await response.json()
    if(!response.ok)throw Error(result.message||'同步失败')
    message.value=`同步完成：厂家 ${result.platformTotal} 台，新增 ${result.added} 台，更新 ${result.updated} 台，其他厂站 ${result.skippedOtherSite} 台。`
    store.revision++;emit('synced')
  } catch(error) { failed.value=true;message.value=error.message }
  finally { busy.value=false }
}
</script>
<template><div class="platform-sync" :aria-busy="busy">
  <button type="button" class="button" :disabled="busy || !provider.canAny('assets:write',store.siteId)" @click="sync">{{ busy?'同步中…':'同步厂家安全帽' }}</button>
  <span class="muted">导入当前厂站；保留既有领用关系和设备资料。状态每 2 分钟刷新。</span>
  <p v-if="message" :class="failed?'error':'notice'" role="status">{{ message }}</p>
</div></template>
<style scoped>.platform-sync{margin:12px 0;display:flex;align-items:center;flex-wrap:wrap;gap:12px}.platform-sync p{flex-basis:100%;margin:0}</style>
