<script setup>
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import AppButton from "@/components/ui/AppButton.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTag from "@/components/ui/AppTag.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import PlantMap from "@/components/domain/PlantMap.vue";
import ConfirmText from "@/components/ui/ConfirmText.vue";
import SosEndActions from "./SosEndActions.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { callPerson, runGuarded } from "@/lib/actions";
import { personName, revision, helmetOf } from "@/lib/queries";
const route = useRoute(), busy = ref(false);
const requests = computed(() => { revision(); return db.state.events.filter(e => e.station === session.station && e.type === "人员求助").sort((a,b) => Number(a.status === "已核验") - Number(b.status === "已核验") || (b.date+b.time).localeCompare(a.date+a.time)); });
const linkedEvent = computed(() => requests.value.find(e => e.id === route.query.eventId));
const alarm = computed(() => { revision(); return linkedEvent.value && db.state.assistance?.[linkedEvent.value.id]; });
const operatorId = computed(() => { revision(); return db.state.operator?.id; });
const readonly = computed(() => linkedEvent.value?.status === "已核验");
const badge = computed(() => ({ waiting: "待接警", accepted: "已接警", active: "正在协助", ended: "协助已结束" })[alarm.value?.status] || "待接警");
const helmet = computed(() => linkedEvent.value && helmetOf(linkedEvent.value.personId));
const canAssist = computed(() => linkedEvent.value?.permissions?.["sos:assist"] && !readonly.value);
async function act(action) {
  if (busy.value || !linkedEvent.value) return; busy.value = true;
  const id = linkedEvent.value.id;
  try { if (action === "claim") await db.claim(id); else await db.sos(action, id); toast(action === "claim" ? "已接警" : "已加入此事件协助"); }
  catch (error) { toast(error.message, true); } finally { busy.value = false; }
}
function endSos() { openModal({ title: "结束前确认", view: ConfirmText, props: { eventId: linkedEvent.value.id, text: "结束本条事件的协助并保留记录，不会自动提交最终核验，也不会结束其他求助。" }, footer: SosEndActions }); }
function memberName(id) { if (id === operatorId.value) return db.state.operator?.name; return alarm.value?.timeline?.find(t => t.actorId === id)?.actorName || (id === "operator" ? "历史值守人员" : personName(id)); }
</script>
<template>
  <PageHeading subtitle="手机与设备求助共用事件流程；接警不依赖语音接通">
    <template #title>SOS协同　<AppTag color="red">SOS</AppTag></template>
    <template #actions><a v-if="linkedEvent" class="btn" :href="'#/event/' + linkedEvent.id"><AppIcon name="arrow-left-line" /> 返回核验</a></template>
  </PageHeading>
  <AppPanel title="求助事件">
    <div v-for="event in requests" :key="event.id" class="participant"><AppIcon name="alarm-warning-line" /><span>{{ event.snapshot?.personName || "未关联人员" }} · {{ event.source === 'manual_sos' ? '手机求助' : '设备求助' }} · {{ event.date }} {{ event.time }} · {{ event.status }}</span><span class="spacer"></span><a class="btn small" :href="'#/sos?eventId=' + event.id">{{ linkedEvent?.id === event.id ? '当前事件' : '打开协助' }}</a></div>
    <AppStatus v-if="!requests.length">当前授权范围暂无求助事件</AppStatus>
    <p v-else-if="!linkedEvent" class="note">请选择一条求助，按事件编号查看对应协助记录。</p>
  </AppPanel>
  <template v-if="linkedEvent && alarm">
    <div class="panel sos-banner">
      <AppIcon name="alarm-warning-fill" /><div><h2>{{ linkedEvent.source === 'manual_sos' ? '手机手动求助' : '设备 SOS 求助' }}</h2><p>{{ linkedEvent.snapshot.personName }} · {{ linkedEvent.id }} · {{ linkedEvent.deviceId || '未关联设备，仍可文字跟进' }}</p></div><span class="session-badge">{{ badge }}</span>
      <div class="heading-actions">
        <AppButton v-if="linkedEvent.permissions?.['events:claim'] && ['待认领','待现场核验'].includes(linkedEvent.status)" tone="primary" :disabled="busy || readonly" @click="act('claim')">接警认领</AppButton>
        <AppButton tone="primary" :disabled="busy || !canAssist || alarm.status === 'ended' || alarm.members.includes(operatorId)" @click="act('join')">加入协助</AppButton>
        <AppButton tone="danger" :disabled="busy || !canAssist || alarm.status === 'ended'" @click="endSos">结束协助</AppButton>
      </div>
    </div>
    <div class="grid sos-layout">
      <AppPanel title="求助位置">
        <PlantMap v-if="linkedEvent.source !== 'manual_sos' && db.locationValid(linkedEvent.personId)" :person="linkedEvent.personId" :legend="false" />
        <p v-else class="note">暂无有效位置；可通过文字说明跟进。</p><p>{{ linkedEvent.locationDescription || linkedEvent.description || '现场情况待补充' }}</p>
      </AppPanel>
      <AppPanel title="设备语音">
        <p>{{ helmet?.online ? '可尝试联系当前领用安全帽' : '没有可用安全帽语音，仍可接警和文字跟进' }}</p>
        <AppButton :disabled="!helmet?.online || readonly" @click="runGuarded(() => callPerson(linkedEvent.personId))">呼叫安全帽</AppButton>
        <p class="note">语音通话与本条协助、最终核验分别处理。</p><a class="btn" :href="'#/event/' + linkedEvent.id">补充现场情况 / 查看核验</a>
      </AppPanel>
      <AppPanel title="协助人员">
        <div v-for="id in alarm.members" :key="id" class="participant"><AppIcon name="user-line" />{{ memberName(id) }}<span class="spacer"></span><AppStatus>已加入</AppStatus></div>
        <AppStatus v-if="!alarm.members.length">暂无人员加入协助</AppStatus><p class="note">{{ readonly ? '已核验记录只读' : '结束协助不代表告警解除或核验完成' }}</p>
      </AppPanel>
    </div>
    <div style="margin-top:15px"><AppPanel title="协助时间线"><div class="timeline horizontal"><div v-for="(item,index) in alarm.timeline" :key="index" class="timeline-item"><time>{{ item.time }}</time>{{ item.actorName ? item.actorName + ' · ' : '' }}{{ item.text }}</div></div></AppPanel></div>
  </template>
</template>
