<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import { db, tick, connection } from '@/mock/runtime';
import { session } from '@/stores/session';
import { deviceCallUnavailable, helmetDeviceCall as call } from '@/lib/helmet-device-call';
import { liveViewing } from '@/lib/live-session';
import { personFeature } from '@/lib/person-equipment';
import { runGuarded, stopRecording, refreshRecording } from '@/lib/actions';
import { COMMAND_STATUSES } from '@/lib/helmet-media';
import { toast } from '@/stores/notify';
import AppButton from '@/components/ui/AppButton.vue';
const state=ref(call.getState()); const unsubscribe=call.subscribe(value=>{state.value=value;});
const active=computed(()=>['requesting','connecting','active','ending','unknown'].includes(state.value.phase));
let endingId='';
watch(()=>[tick.value,connection.value.status,session.station,state.value.callId],()=>{
  if (!active.value) { endingId=''; return; }
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
  if (!session.recording?.real || checkingRecording) return;
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
const recordingTimer = setInterval(checkRecording, 5000);
watch(()=>[tick.value,session.station,session.recording?.startKey],()=>{void checkRecording();});
watch(()=>session.station,()=>{void liveViewing.dispose();});
onUnmounted(()=>{clearInterval(recordingTimer);unsubscribe();void liveViewing.dispose();if(active.value)void call.end().catch(()=>{});if(session.recording?.real)void stopRecording().catch(()=>{});});
</script>
<template>
  <div v-if="active || session.recording?.real" class="device-session-bar" role="status">
    <template v-if="active"><span>{{ db.person(state.personId)?.name || '人员' }}的语音会话：{{ state.endRequested ? '正在结束' : state.phase === 'active' ? '通话中' : state.phase === 'unknown' ? '结果待确认' : '等待设备接通' }}</span><a class="btn small" :href="'#/dispatch?personId='+encodeURIComponent(state.personId || '')">调度通信</a><AppButton tone="small" @click="runGuarded(() => call.end())">结束通话</AppButton></template>
    <template v-if="session.recording?.real"><span>{{ db.person(session.recording.person)?.name }}的录像请求：{{ COMMAND_STATUSES[session.recording.status] || '等待录制回执' }}</span><AppButton v-if="session.recording.status !== 'finalizing'" tone="small" @click="runGuarded(stopRecording)">结束录像请求</AppButton></template>
  </div>
</template>
<style scoped>.device-session-bar{display:flex;flex-wrap:wrap;align-items:center;justify-content:center;gap:12px;padding:8px 20px;background:var(--theme-card);border-bottom:1px solid var(--theme-border)}</style>
