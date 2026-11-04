<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import { db, tick, connection } from '@/mock/runtime';
import { session } from '@/stores/session';
import { deviceCallStatus, deviceCallUnavailable, helmetDeviceCall as call } from '@/lib/helmet-device-call';
import { liveViewing } from '@/lib/live-session';
import { personFeature } from '@/lib/person-equipment';
import { runGuarded, stopRecording, refreshRecording } from '@/lib/actions';
import { COMMAND_STATUSES } from '@/lib/helmet-media';
import { toast } from '@/stores/notify';
import AppButton from '@/components/ui/AppButton.vue';
const props = defineProps({ voiceOnly: { type: Boolean, default: false } });
const state=ref(call.getState()); const unsubscribe=call.subscribe(value=>{state.value=value;});
const active=computed(()=>['requesting','connecting','active','ending','unknown'].includes(state.value.phase));
watch([() => { tick.value; return db.state.operator?.id; }, () => connection.value.status], ([operatorId, status]) => {
  if (operatorId && status === 'online') void call.recover({ operatorId }).catch(() => {});
}, { immediate: true });
let endingId='';
watch(()=>[tick.value,connection.value.status,session.station,state.value.callId],()=>{
  if (!active.value) { endingId=''; return; }
  if (state.value.recovered) return;
  if (state.value.endRequested) return;
  const current=personFeature(db,state.value.personId,'voice');
  const key=[state.value.deviceId,state.value.assignmentId,state.value.assignmentVersion].join('/');
  const assignment = { personId: state.value.personId, deviceId: state.value.deviceId, assignmentId: state.value.assignmentId, assignmentVersion: state.value.assignmentVersion };
  const unavailable = deviceCallUnavailable(db.device(state.value.deviceId), current, false, assignment, { acceptanceTest: state.value.acceptanceTest === true, operator: db.state.operator });
  if ((unavailable || db.person(state.value.personId)?.station!==session.station) && endingId!==key) {
    endingId=key; void call.end().catch(()=>{});
  }
});
let checkingRecording = false;
async function checkRecording() {
  if (props.voiceOnly || !session.recording?.real || checkingRecording) return;
  checkingRecording = true;
  try {
    const ended = await refreshRecording();
    if (ended) toast(ended.message || COMMAND_STATUSES[ended.status] || '录像请求已结束', ['failed','rejected','timeout'].includes(ended.status));
    const recording = session.recording;
    if (!recording?.real || recording.stopRequested) return;
    const current = personFeature(db, recording.person, 'recording');
    if (!current.available || current.assignmentId !== recording.context.assignmentId || current.assignmentVersion !== recording.context.assignmentVersion || db.person(recording.person)?.station !== session.station) await stopRecording();
  } catch { /* Keep the original session visible for explicit retry. */ }
  finally { checkingRecording = false; }
}
const recordingTimer = props.voiceOnly ? undefined : setInterval(checkRecording, 5000);
watch(()=>[tick.value,session.station,session.recording?.startKey],()=>{void checkRecording();});
watch(()=>session.station,()=>{if(!props.voiceOnly)void liveViewing.dispose();});
onUnmounted(()=>{clearInterval(recordingTimer);unsubscribe();if(!props.voiceOnly){void liveViewing.dispose();if(session.recording?.real)void stopRecording().catch(()=>{});}});
</script>
<template>
  <div v-if="active || (!voiceOnly && session.recording?.real)" class="device-session-bar" role="status">
    <template v-if="active"><span>{{ db.person(state.personId)?.name || '人员' }}的语音会话：{{ deviceCallStatus(state) }}</span><a class="btn small" :href="'#/dispatch?personId='+encodeURIComponent(state.personId || '')">调度通信</a><AppButton tone="small" @click="runGuarded(() => call.refresh())">刷新状态</AppButton><AppButton tone="small" @click="runGuarded(() => call.end())">{{ state.recovered ? '结束已有会话' : '结束通话' }}</AppButton></template>
    <template v-if="!voiceOnly && session.recording?.real"><span>{{ db.person(session.recording.person)?.name }}的平台录制：{{ COMMAND_STATUSES[session.recording.status] || '等待录制回执' }}</span><AppButton v-if="session.recording.status !== 'finalizing'" tone="small" @click="runGuarded(stopRecording)">停止平台录制</AppButton></template>
  </div>
</template>
<style scoped>.device-session-bar{display:flex;flex-wrap:wrap;align-items:center;justify-content:center;gap:12px;padding:8px 20px;background:var(--theme-card);border-bottom:1px solid var(--theme-border)}</style>
