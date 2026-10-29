<script setup>
import { computed, ref, watch } from "vue";
import { useRoute } from 'vue-router';
import { useFieldErrors } from "@ui-spec/useFieldErrors";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppIcon from "@/components/ui/AppIcon.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppPanel from "@/components/ui/AppPanel.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import AppStatus from "@/components/ui/AppStatus.vue";
import AppTabs from "@/components/ui/AppTabs.vue";
import AppTag from "@/components/ui/AppTag.vue";
import AppTextarea from "@/components/ui/AppTextarea.vue";
import PageHeading from "@/components/layout/PageHeading.vue";
import CallVideos from "@/components/domain/CallVideos.vue";
import PersonAvatar from "@/components/domain/PersonAvatar.vue";
import BroadcastPreview from "./BroadcastPreview.vue";
import BroadcastRecords from "./BroadcastRecords.vue";
import CallRecords from "./CallRecords.vue";
import GroupForm from "./GroupForm.vue";
import InviteForm from "./InviteForm.vue";
import { db, refreshSnapshot } from "@/mock/runtime";
import PersonCall from './PersonCall.vue';
import { personFeature, personDevice, operationContext } from '@/lib/person-equipment';
import { authFetch } from '@/lib/auth';
import { sharedCalls, sharedBroadcasts } from '@/lib/shared-communications';
import { formatBeijingDateTime } from '@/lib/date-time';
import { deviceStatus } from "@/lib/device-telemetry";
import { resumeAudio } from '@/lib/rtc';
import { filtersOf, session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { runGuarded } from "@/lib/actions";
import { helmetOf, people, personName, revision, search } from "@/lib/queries";
import { featureState } from '../../../../shared/device-features.mjs';
const route = useRoute();
const selectedPerson = computed(() => { revision(); const ids=session.selectedMembers.filter(id=>people().some(p=>p.id===id));return ids.length===1?ids[0]:''; });
const voice = computed(()=>personFeature(db,selectedPerson.value,'voice'));
const broadcastFeature = computed(()=>{
  revision();const group=groups.value.find(g=>g.id===broadcastGroupId.value);
  const list=(group?.members||[]).map(id=>personFeature(db,id,'broadcast'));
  const supported=people().some(p=>personFeature(db,p.id,'broadcast').supported);
  return {supported,verified:list.length>0&&list.every(f=>f.verified),available:list.length>0&&list.every(f=>f.available),reason:!list.length?'请选择接收分组':list.find(f=>!f.available)?.reason||'',recipients:list};
});
watch(()=>{revision();const id=route.query.personId;return typeof id==='string'&&db.person(id)?id:'';},id=>{if(id)session.selectedMembers=[id];},{immediate:true});

const BROADCAST_DEFAULT = "";
const dispatchTabs = [
  { id: "people", label: "人员" },
  { id: "groups", label: "协助分组" },
];

const storedDraft = typeof session.broadcastDraft === "string" ? session.broadcastDraft : "";
const broadcastText = ref(storedDraft || BROADCAST_DEFAULT);
const charCount = ref("最多 200 字");
const broadcastError = ref("");
const broadcastGroupId = ref("");
const { formRef: broadcastFormRef, errors: broadcastErrors, validate: validateBroadcast } = useFieldErrors(() => ({ groupId: broadcastGroupId.value, text: broadcastText.value }));
const queryDraft = ref(filtersOf("dispatch").q || "");
const videoCall = ref(false);
let lastBroadcast = 0;
const broadcasting=ref(false);
let broadcastRequest;

const groups = computed(() => {
  revision();
  return db.state.groups.filter((group) => group.station === session.station);
});

const currentGroup = computed(() => {
  revision();
  return groups.value.find((group) => group.id === session.group) || groups.value[0] || null;
});

const groupOptions = computed(() => {
  revision();
  return groups.value.map((group) => [group.id, group.name]);
});

const visiblePeople = computed(() => {
  revision();
  const term = filtersOf("dispatch").q || "";
  return people().filter((person) =>
    search(person.name + " " + db.currentDevices(person.id).map((device) => device.id).join(" "), term),
  );
});

const selectedCount = computed(() => {
  revision();
  const ids = new Set(people().map((person) => person.id));
  return session.selectedMembers.filter((id) => ids.has(id)).length;
});

const allVisibleSelected = computed(() => {
  revision();
  const list = visiblePeople.value;
  return !!list.length && list.every((person) => session.selectedMembers.includes(person.id));
});

const activeCall = computed(() => {
  revision();
  return db.state.calls.find((call) => call.station === session.station && call.status !== "已结束") || null;
});

const recentCalls = computed(() => {
  revision();
  return [...sharedCalls(session.station),...db.state.calls.filter((call) => call.station === session.station)].sort((a,b)=>String(b.time).localeCompare(String(a.time))).slice(0, 3);
});

const recentBroadcasts = computed(() => {
  revision();
  return [...sharedBroadcasts(session.station),...db.state.broadcasts.filter((item) => item.station === session.station)].sort((a,b)=>String(b.time).localeCompare(String(a.time))).slice(0, 3);
});

const showGroupEditor = computed(() => {
  revision();
  return !!currentGroup.value && (session.dispatchTab || "people") === "groups";
});

watch(
  groups,
  (list) => {
    if (list.length && !list.some((group) => group.id === session.group)) session.group = list[0].id;
    if (!list.some((group) => group.id === broadcastGroupId.value)) {
      broadcastGroupId.value = list.find((group) => group.id === session.group)?.id || list[0]?.id || "";
    }
  },
  { immediate: true },
);

watch(
  () => session.group,
  (id) => {
    if (groups.value.some((group) => group.id === id)) broadcastGroupId.value = id;
  },
);

watch(
  () => session.filters.dispatch?.q || "",
  (value) => {
    queryDraft.value = value;
  },
);

function applySearch() {
  session.filters.dispatch = { q: queryDraft.value };
}

function resetSearch() {
  queryDraft.value = "";
  session.filters.dispatch = {};
}

function selectGroup(id) {
  const group = groups.value.find((item) => item.id === id);
  if (!group) return;
  session.group = group.id;
  session.selectedMembers = [...group.members];
}

function toggleVisible(event) {
  const visibleIds = visiblePeople.value.map((person) => person.id);
  session.selectedMembers = event.target.checked
    ? [...new Set([...session.selectedMembers, ...visibleIds])]
    : session.selectedMembers.filter((id) => !visibleIds.includes(id));
}

function toggleMember(id, checked) {
  session.selectedMembers = checked
    ? [...new Set([...session.selectedMembers, id])]
    : session.selectedMembers.filter((item) => item !== id);
}

function memberText(personId) {
  const feature=personFeature(db,personId,'voice');
  return feature.available ? '可呼叫' : feature.reason;
}

function joined(call, personId) {
  return call.rtc ? call.serverConnected === true && call.connectedDeviceIds?.includes(helmetOf(personId)?.id) : !!call.joined?.includes(personId);
}

function callNames(call) {
  return (call.members || []).map((id) => personName(id)).join("、");
}

function openGroup(id = "") {
  const groupId = typeof id === "string" ? id : "";
  openModal({
    title: groupId ? "编辑协助分组" : "新建协助分组",
    view: GroupForm,
    layout: "form",
    props: { groupId },
  });
}

function openInvite(id) {
  openModal({
    title: "邀请成员",
    view: InviteForm,
    size: "compact",
    layout: "form",
    props: { callId: id },
  });
}

function openRecords() {
  openModal({ title: "通信记录", wide: true, view: CallRecords });
}

function openBroadcasts() {
  openModal({ title: "广播记录", wide: true, view: BroadcastRecords });
}

function startCall(kind) {
  runGuarded(async () => {
    const ids = session.selectedMembers.filter((id) => people().some((person) => person.id === id));
    await db.startCall(ids, kind, session.station, { video: videoCall.value });
    toast("呼叫已发起");
  });
}

function connectCall(id) {
  runGuarded(async () => {
    await db.updateCall(id, "connect");
    toast("本端已加入，设备接通状态以服务端回执为准");
  });
}

function endCall(id) {
  runGuarded(async () => {
    await db.updateCall(id, "end");
    toast(db.state.calls.find(call=>call.id===id)?.status==='正在结束'?'已请求结束，等待服务器确认':'通话已结束，记录已保存');
  });
}

function muteCall(id) {
  runGuarded(async () => {
    await db.updateCall(id, "mute");
  });
}

function setBroadcast(value) {
  broadcastText.value = value;
  session.broadcastDraft = value;
  charCount.value = String(value).length + "/200";
}

function previewBroadcast() {
  const text = broadcastText.value.trim();
  if (!validateBroadcast({ text: !text ? '请输入广播内容' : text.length > 200 ? '广播内容最多200字' : '' })) return;
  const synth = window.speechSynthesis;
  if (!synth || typeof synth.speak !== "function") {
    openModal({ title: "广播试听", view: BroadcastPreview, props: { text } });
    toast("当前浏览器未提供语音合成，可预览广播文字。", true);
    return;
  }
  try {
    synth.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = "zh-CN";
    utterance.onerror = (event) => {
      if (event.error === "canceled" || event.error === "interrupted") return;
      toast("广播试听失败", true);
    };
    synth.speak(utterance);
    toast("正在试听广播");
  } catch {
    toast("广播试听失败", true);
  }
}

async function sendBroadcast() {
  if (!validateBroadcast({ groupId: !broadcastGroupId.value && '请选择广播对象', text: !broadcastText.value.trim() ? '请输入广播内容' : broadcastText.value.length > 200 ? '广播内容最多200字' : '' })) return;
  const now = Date.now();
  if (broadcasting.value || now - lastBroadcast < 1000) return;
  lastBroadcast = now;
  broadcastError.value = "";
  broadcasting.value=true;
  try {
    if(db.demoMode) db.broadcast(broadcastGroupId.value, broadcastText.value);
    else {
      if(!broadcastFeature.value.available)throw Error(broadcastFeature.value.reason);
      const payload={recipients:broadcastFeature.value.recipients.map(operationContext),text:broadcastText.value.trim()};
      const identity=JSON.stringify(payload);
      if(broadcastRequest?.identity!==identity)broadcastRequest={identity,key:crypto.randomUUID()};
      const response=await authFetch('/api/guardian/v1/mobile/broadcast',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...payload,idempotencyKey:broadcastRequest.key})});
      const result=await response.json().catch(()=>({}));
      if(!response.ok)throw Error(result.message||'广播请求失败');
      if(!Array.isArray(result)||result.some(row=>!['accepted','completed'].includes(row.status)))throw Error('广播结果未确认，可重试查询同一请求');
      broadcastRequest=null;await refreshSnapshot();
    }
    session.broadcastDraft = "";
    broadcastText.value = BROADCAST_DEFAULT;
    charCount.value = "最多 200 字";
    toast(db.demoMode ? "模拟广播记录已保存" : "广播请求已受理，实际播放结果以设备回执为准");
  } catch (error) {
    broadcastError.value = error.message || "操作失败";
  } finally { broadcasting.value=false; }
}
</script>

<template>
  <PageHeading title="人员联络、协助分组与广播" subtitle="调度通信 / 调度台">
    <template #actions>
      <AppButton icon="file-list-3-line" @click="openRecords">通信记录</AppButton>
    </template>
  </PageHeading>
  <div class="grid dispatch-layout">
    <AppPanel title="人员与分组">
      <AppTabs :model-value="session.dispatchTab || 'people'" :tabs="dispatchTabs" @update:model-value="session.dispatchTab = $event" />
      <form class="filters" data-form="filters" @submit.prevent="applySearch">
        <div class="searchbox">
          <AppIcon name="search-line" />
          <AppInput v-model="queryDraft" name="q" placeholder="姓名 / 设备编号" />
        </div>
        <AppButton type="submit" tone="primary" icon="search-line">查询</AppButton>
        <AppButton type="button" icon="refresh-line" @click="resetSearch">重置</AppButton>
      </form>
      <div class="row space-between">
        <span class="muted">协助分组</span>
        <AppButton tone="plain blue" icon="add-line" @click="openGroup()">新建分组</AppButton>
      </div>
      <div v-for="group in groups" :key="group.id" class="group-row" :class="{ selected: currentGroup && group.id === currentGroup.id }" @click="selectGroup(group.id)">
        <AppIcon name="group-line" />{{ group.name }}<small>{{ group.members.length }} 人</small>
      </div>
      <div v-if="showGroupEditor" class="form-actions">
        <AppButton tone="wide" icon="edit-line" @click="openGroup(currentGroup.id)">编辑分组成员</AppButton>
      </div>
      <div class="row space-between" style="margin:20px 0 8px">
        <span>人员（{{ visiblePeople.length }}人）</span>
        <label class="row"><input type="checkbox" :checked="allVisibleSelected" @change="toggleVisible" />全选</label>
      </div>
      <div class="member-list">
        <label v-for="person in visiblePeople" :key="person.id" class="member-row">
          <input type="checkbox" :checked="session.selectedMembers.includes(person.id)" @change="toggleMember(person.id, $event.target.checked)" />
          <PersonAvatar :person="person" />
          <span>{{ person.name }}<small style="display:block">{{ personDevice(db,person.id,'voice')?.id || '未领用通信设备' }}</small></span>
          <AppStatus :color="personFeature(db,person.id,'voice').available ? 'green' : 'muted'">{{ memberText(person.id) }}</AppStatus>
        </label>
      </div>
      <div class="form-actions">
        <span class="muted">已选 {{ selectedCount }} 人</span>
        <AppButton v-if="db.demoMode" @click="startCall('单呼')">单呼（演示）</AppButton>
        <AppButton v-if="db.demoMode" tone="primary" @click="startCall('群呼')">发起群呼（演示）</AppButton>
      </div>
    </AppPanel>
    <div class="stack">
      <PersonCall v-if="!db.demoMode" :person-id="selectedPerson" />
      <AppPanel v-else :title="'当前通话：' + (activeCall ? activeCall.kind : '未发起')">
        <template v-if="activeCall">
          <div class="call-status">
            <AppIcon :name="activeCall.status === '通话中' ? 'phone-fill' : 'phone-find-line'" />{{ "　" + (activeCall.statusLabel || (activeCall.rtc ? "设备接通待确认" : activeCall.status)) }}
          </div>
          <CallVideos :call="activeCall" />
          <AppButton v-if="activeCall.connectionQuality === 'playback_blocked'" @click="runGuarded(resumeAudio)">播放通话声音</AppButton>
          <div v-for="personId in activeCall.members" :key="personId" class="call-member">
            <PersonAvatar :person="db.person(personId)" />
            <div>{{ personName(personId) }}{{ "　" }}<small>{{ helmetOf(personId)?.id || "未绑定" }}</small></div>
            <AppStatus :color="joined(activeCall, personId) ? 'green' : 'yellow'">{{ joined(activeCall, personId) ? "已接通" : "设备接通待确认" }}</AppStatus>
            <AppIcon name="voiceprint-line" />
          </div>
          <div class="form-actions">
            <AppButton tone="danger" icon="phone-fill" @click="endCall(activeCall.id)">{{ activeCall.status === "正在呼叫" ? "取消呼叫" : "结束通话" }}</AppButton>
            <AppButton icon="mic-off-line" @click="muteCall(activeCall.id)">{{ activeCall.muted ? "取消静音" : "静音" }}</AppButton>
            <AppButton v-if="!activeCall.rtc" icon="user-add-line" @click="openInvite(activeCall.id)">邀请成员</AppButton>
          </div>
          <div v-if="activeCall.status === '正在呼叫' && (!activeCall.connectionQuality || activeCall.connectionQuality === 'requesting')" class="form-actions">
            <AppButton tone="primary wide" icon="phone-line" @click="connectCall(activeCall.id)">加入语音</AppButton>
          </div>
        </template>
        <template v-else>
          <AppEmpty text="选择人员后发起单呼或群呼" />
          <p class="note">通信通道兼容性待联调。</p>
        </template>
      </AppPanel>
      <AppPanel v-if="broadcastFeature.supported" :title="broadcastFeature.verified ? '文字广播' : '文字广播 · 待联调'">
        <form ref="broadcastFormRef" novalidate class="broadcast-box" data-form="broadcast" @submit.prevent="sendBroadcast">
          <AppField label="广播对象" vertical data-field="groupId" :error="broadcastErrors.groupId">
            <AppSelect v-model="broadcastGroupId" name="groupId" :options="groupOptions" />
          </AppField>
          <AppField label="广播内容" vertical data-field="text" :error="broadcastErrors.text"><AppTextarea name="text" maxlength="200" placeholder="请输入广播内容" :model-value="broadcastText" @update:model-value="setBroadcast" /></AppField>
          <div class="char-count">{{ charCount }}</div>
          <div class="form-actions">
            <AppButton type="button" icon="play-fill" @click="previewBroadcast">本机试听</AppButton>
            <AppButton type="submit" tone="primary" icon="send-plane-fill" :disabled="!broadcastFeature.available || broadcasting">{{ broadcasting ? '正在提交…' : '发送广播' }}</AppButton>
          </div>
          <p v-if="!broadcastFeature.available" class="muted">{{ broadcastFeature.reason }}</p>
          <p v-if="broadcastError" class="form-error" role="alert">{{ broadcastError }}</p>
        </form>
      </AppPanel>
    </div>
    <div class="stack">
      <AppPanel title="最近会话">
        <template #extra><AppButton tone="plain" @click="openRecords">更多 <UiIcon name="chevron-right" /></AppButton></template>
        <template v-if="recentCalls.length">
          <div v-for="call in recentCalls" :key="call.id" class="record-entry">
            <time>{{ formatBeijingDateTime(call.time) }}</time>
            <h3><AppIcon name="user-voice-line" color="blue" />{{ "　" + call.kind + " · " + (callNames(call) || '未关联人员') }}</h3>
            <p><AppStatus :color="call.status === '已结束' ? 'green' : 'yellow'">{{ call.status === '已结束' ? call.status : call.statusLabel || (call.rtc ? '设备接通待确认' : call.status) }}</AppStatus></p>
          </div>
        </template>
        <AppEmpty v-else text="暂无通信记录" />
      </AppPanel>
      <AppPanel title="广播记录">
        <template #extra><AppButton tone="plain" @click="openBroadcasts">更多 <UiIcon name="chevron-right" /></AppButton></template>
        <template v-if="recentBroadcasts.length">
          <div v-for="item in recentBroadcasts" :key="item.id" class="record-entry">
            <time>{{ item.time.slice(11, 16) }}</time>
            <h3><AppIcon name="volume-up-fill" />{{ "　" + item.groupName }}</h3>
            <p>{{ item.text }}</p>
            <AppTag color="green">{{ item.status }}</AppTag>
          </div>
        </template>
        <AppEmpty v-else text="暂无广播记录" />
      </AppPanel>
      <p class="note"><AppIcon name="information-line" />通话记录与广播回执分别留存。</p>
    </div>
  </div>
</template>
