<script setup>
import { computed } from 'vue';
import { db, tick } from '@/mock/runtime';
import { session } from '@/stores/session';
const props=defineProps({details:Boolean});
const rows=computed(()=>{tick.value;return db.state.devices.filter(d=>d.source==='PLATFORM'&&d.station===session.station)});
function current(d){return d.freshness==='CURRENT'&&Number.isFinite(Date.parse(d.updated))&&Date.now()-Date.parse(d.updated)<=300000}
function status(d){return !current(d)||d.online==null?'待刷新':d.online?'在线':'离线'}
function wearer(d){const b=db.state.bindings.find(b=>b.deviceId===d.id&&!b.end);return b?db.person(b.personId)?.name||'待核对':'未领用'}
const online=computed(()=>rows.value.filter(d=>current(d)&&d.online===true).length);
const offline=computed(()=>rows.value.filter(d=>current(d)&&d.online===false).length);
const unassigned=computed(()=>rows.value.filter(d=>wearer(d)==='未领用').length);
const stamp=computed(()=>{tick.value;return Object.values(db.state.platformSync||{}).find(s=>s.station===session.station)?.lastSuccessAt});
function date(value){return value?new Date(value).toLocaleString('zh-CN',{hour12:false}):'尚未同步'}
</script>
<template><section class="platform-equipment" aria-label="厂家安全帽">
  <div class="platform-heading"><strong>厂家安全帽 <small>真实查询</small></strong><span>共 {{ rows.length }} 台 · 在线 {{ online }} · 离线 {{ offline }} · 待刷新 {{ rows.length-online-offline }} · 未领用 {{ unassigned }}</span></div>
  <p>最近同步：{{ date(stamp) }}。未领用设备也计入此处；其他人员、作业和监护统计仍含示例数据。</p>
  <div v-if="props.details" class="platform-table"><table><thead><tr><th>设备编号</th><th>通信状态</th><th>领用人员</th><th>电量</th><th>定位 / 佩戴状态</th></tr></thead><tbody>
    <tr v-for="d in rows" :key="d.id"><td>{{ d.id }}</td><td>{{ status(d) }}</td><td>{{ wearer(d) }}</td><td>{{ d.battery==null?'未知':d.battery+'%' }}</td><td>待设备上报核验</td></tr>
    <tr v-if="!rows.length"><td colspan="5">暂无厂家安全帽，请在后台设备台账同步。</td></tr>
  </tbody></table></div>
</section></template>
<style scoped>
.platform-equipment{padding:12px 16px;margin:0 0 14px;border:1px solid #126486;background:#002638;color:#d9f3ff}.platform-heading{display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap}.platform-heading small{color:#31dfbf;margin-left:8px;font-weight:400}.platform-equipment p{font-size:12px;color:#99bfce;margin:6px 0 0}.platform-table{overflow:auto;margin-top:12px}.platform-table table{width:100%;text-align:left;border-collapse:collapse}.platform-table td,.platform-table th{padding:9px;border-bottom:1px solid #164659;white-space:nowrap}
</style>
