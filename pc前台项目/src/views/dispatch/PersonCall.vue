<script setup>
import { computed, onUnmounted, ref } from 'vue';
import AppButton from '@/components/ui/AppButton.vue';
import AppPanel from '@/components/ui/AppPanel.vue';
import { db, tick, connection, refreshSnapshot } from '@/mock/runtime';
import { personFeature, operationContext } from '@/lib/person-equipment';
import { deviceCallStatus, deviceCallUnavailable, helmetDeviceCall as call } from '@/lib/helmet-device-call';
const props = defineProps({ personId: { type: String, default: '' }, selectedCount: { type: Number, default: 0 } });
const state = ref(call.getState()), error = ref(''), preparing = ref(false);
const unsubscribe = call.subscribe(value => { state.value = value; }); onUnmounted(unsubscribe);
const feature = computed(() => { tick.value; return personFeature(db, props.personId, 'voice'); });
const active = computed(() => ['requesting','connecting','active','ending','unknown'].includes(state.value.phase));
const status = computed(() => deviceCallStatus(state.value));
const unavailable = computed(() => {
  if (!props.personId) return props.selectedCount > 1 ? '语音通话每次联系一人，请只选择一名人员' : '请在左侧选择一名人员';
  if (!feature.value.supported) return feature.value.reason || '未领用支持语音通话的安全帽';
  if (connection.value.status !== 'online') return '业务后台未连接';
  try { return deviceCallUnavailable(db.device(feature.value.deviceId), feature.value, false, operationContext(feature.value)); }
  catch (reason) { return reason.message; }
});
async function act(fn) { error.value='';try { await fn(); } catch(reason) { error.value=reason.message || '通信请求失败'; } }
async function start() {
  if (unavailable.value || preparing.value || active.value || state.value.recovering) return;
  preparing.value=true;
  await act(async () => {
    const context=operationContext(feature.value);
    const current=personFeature(db,props.personId,'voice');
    const reason = deviceCallUnavailable(db.device(context.deviceId), current, false, context);
    if (reason) throw Error(reason);
    await call.start(db.device(context.deviceId),current,false,context);
    await refreshSnapshot();
  });
  preparing.value=false;
}
</script>
<template>
  <AppPanel title="语音通话">
    <p v-if="personId">{{ db.person(personId)?.name }} · {{ feature.deviceId || '未领用安全帽' }}</p>
    <p v-if="unavailable" class="muted" role="status">{{ unavailable }}</p>
    <AppButton v-if="personId" :disabled="!!unavailable || active || preparing || state.recovering" tone="primary" icon="phone-line" @click="start()">{{ preparing ? '正在准备…' : '发起语音通话' }}</AppButton>
    <p v-if="state.recoveryError" role="alert" class="form-error">{{ state.recoveryError }}</p>
    <AppButton v-if="state.recoveryError && !active" tone="small" :disabled="state.recovering" @click="act(() => call.recover({ operatorId: db.state.operator?.id, deviceId: feature.deviceId }))">{{ state.recovering ? '正在检查…' : '重试检查' }}</AppButton>
    <div v-if="active || state.recordId || state.error || state.recovering" class="detail-section">
      <p role="status">{{ db.person(state.personId)?.name || state.personId }} · {{ state.deviceId }} · {{ status }}</p>
      <p v-if="state.acceptanceTest" class="muted">历史测试会话</p>
      <p v-if="state.recovered" class="muted">检测到已有通话，本页尚未加入。可结束已有通话后重新呼叫。</p>
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
