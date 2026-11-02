<script setup>
import { computed, onUnmounted, ref, watch } from 'vue';
import AppButton from '@/components/ui/AppButton.vue';
import AppPanel from '@/components/ui/AppPanel.vue';
import { db, tick, connection, refreshSnapshot } from '@/mock/runtime';
import { personFeature, operationContext } from '@/lib/person-equipment';
import { deviceCallStatus, deviceCallUnavailable, helmetDeviceCall as call } from '@/lib/helmet-device-call';
const props = defineProps({ personId: { type: String, default: '' } });
const state = ref(call.getState()), error = ref(''), preparing = ref(false);
const acceptanceEnabled = ref(false);
const unsubscribe = call.subscribe(value => { state.value = value; }); onUnmounted(unsubscribe);
const feature = computed(() => { tick.value; return personFeature(db, props.personId, 'voice'); });
const active = computed(() => ['requesting','connecting','active','ending','unknown'].includes(state.value.phase));
const status = computed(() => deviceCallStatus(state.value));
const unavailable = computed(() => !props.personId ? '请选择一名人员' : !feature.value.supported ? '该人员没有已领用的通信设备' : !feature.value.available ? feature.value.reason : connection.value.status !== 'online' ? '业务后台未连接' : '');
const testEntry = computed(() => {
  tick.value;
  const device = db.device(feature.value.deviceId);
  return db.state.operator?.id === 'demo-system' && db.state.operator?.enabled !== false && feature.value.supported && !feature.value.verified && device?.source === 'DIRECT_HELMET' && device.type === 'H';
});
const testUnavailable = computed(() => {
  if (!testEntry.value || !acceptanceEnabled.value) return '请先显式启用本次语音联调测试';
  if (connection.value.status !== 'online') return '业务后台未连接';
  try { return deviceCallUnavailable(db.device(feature.value.deviceId), feature.value, false, operationContext(feature.value), { acceptanceTest: true, operator: db.state.operator }); }
  catch (reason) { return reason.message; }
});
watch(() => JSON.stringify([props.personId, feature.value.deviceId, feature.value.assignmentId, feature.value.assignmentVersion, db.state.operator?.id, testEntry.value]), () => { acceptanceEnabled.value = false; });
async function act(fn) { error.value='';try { await fn(); } catch(reason) { error.value=reason.message || '通信请求失败'; } }
async function start(acceptanceTest = false) {
  const testing = acceptanceTest === true;
  if ((testing ? testUnavailable.value : unavailable.value) || preparing.value || active.value || state.value.recovering) return;
  preparing.value=true;
  await act(async () => {
    const context=operationContext(feature.value);
    const current=personFeature(db,props.personId,'voice');
    const options = { acceptanceTest: testing, operator: db.state.operator };
    const reason = deviceCallUnavailable(db.device(context.deviceId), current, false, context, options);
    if (reason) throw Error(reason);
    await call.start(db.device(context.deviceId),current,false,context,options);
    await refreshSnapshot();
  });
  if (testing) acceptanceEnabled.value=false;
  preparing.value=false;
}
</script>
<template>
  <AppPanel title="语音通话">
    <p v-if="personId">{{ db.person(personId)?.name }} · {{ feature.deviceId || '无通信设备' }}</p>
    <p v-if="unavailable" class="muted">{{ unavailable }}</p>
    <AppButton v-if="feature.supported" :disabled="!!unavailable || active || preparing || state.recovering" tone="primary" icon="phone-line" @click="start()">{{ preparing ? '正在准备…' : feature.available ? '呼叫该人员' : feature.reason }}</AppButton>
    <section v-if="testEntry" class="detail-section" aria-label="语音联调测试">
      <label><input v-model="acceptanceEnabled" type="checkbox" :disabled="active || preparing || state.recovering"> 启用本次语音联调测试</label>
      <p class="muted">仅系统管理员使用。请确认现场人员已准备；本次测试仍校验领用、在线和接入状态，不会改变正式验收状态。</p>
      <AppButton :disabled="!!testUnavailable || active || preparing || state.recovering" @click="start(true)">发起语音联调测试</AppButton>
      <p v-if="acceptanceEnabled && testUnavailable" role="status" class="muted">{{ testUnavailable }}</p>
    </section>
    <p v-if="state.recoveryError" role="alert" class="form-error">{{ state.recoveryError }}</p>
    <AppButton v-if="state.recoveryError && !active" tone="small" :disabled="state.recovering" @click="act(() => call.recover({ operatorId: db.state.operator?.id, deviceId: feature.deviceId }))">{{ state.recovering ? '正在检查…' : '重试检查' }}</AppButton>
    <div v-if="active || state.recordId || state.error || state.recovering" class="detail-section">
      <p role="status">{{ db.person(state.personId)?.name || state.personId }} · {{ state.deviceId }} · {{ status }}</p>
      <p v-if="state.acceptanceTest" class="muted">本次为语音联调测试，设备语音仍未正式验收。</p>
      <p v-if="state.recovered" class="muted">此页只恢复会话状态，未打开麦克风或加入通话。请核实原页面；需要结束时使用下方按钮。</p>
      <p v-if="state.clientStatus==='remote_audio'" class="muted">已收到远端音频，接听设备身份仍以服务端确认结果为准。</p>
      <div v-if="active" class="form-actions">
        <AppButton tone="danger" @click="act(() => call.end())">{{ state.endRequested ? '重试结束' : state.recovered ? '结束已有会话' : '结束通话' }}</AppButton>
        <AppButton :disabled="state.endRequested || !['local_joined','remote_audio','playback_blocked'].includes(state.clientStatus)" @click="act(() => call.setMuted(!state.muted))">{{ state.muted ? '开启麦克风' : '麦克风静音' }}</AppButton>
        <AppButton :disabled="state.pending" @click="act(() => call.refresh())">刷新通话状态</AppButton>
        <AppButton v-if="state.clientStatus==='playback_blocked'" @click="act(() => call.resumeAudio())">播放通话声音</AppButton>
      </div>
      <p v-if="state.error" role="alert" class="form-error">{{ state.error }}</p>
    </div>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
  </AppPanel>
</template>
