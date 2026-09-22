<script setup>
import { computed, ref, watch } from "vue";
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
import { db } from "@/mock/runtime";
import { filtersOf, session } from "@/stores/session";
import { openModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { runGuarded } from "@/lib/actions";
import { helmetOf, people, personName, revision, search } from "@/lib/queries";

const BROADCAST_DEFAULT = "请锅炉平台作业人员检查随身装备，保持通信畅通。";
const dispatchTabs = [
  { id: "people", label: "人员" },
  { id: "groups", label: "协助分组" },
];

const storedDraft = typeof session.broadcastDraft === "string" ? session.broadcastDraft : "";
const broadcastText = ref(storedDraft || BROADCAST_DEFAULT);
const charCount = ref("最多 200 字");
const broadcastError = ref("");
const broadcastGroupId = ref("");
const queryDraft = ref(filtersOf("dispatch").q || "");
let lastBroadcast = 0;

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
  return db.state.calls.filter((call) => call.station === session.station).slice(0, 3);
});

const recentBroadcasts = computed(() => {
  revision();
  return db.state.broadcasts.filter((item) => item.station === session.station).slice(0, 3);
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
  const helmet = helmetOf(personId);
  if (helmet?.online) return "在线";
  if (helmet) return "连接中断";
  return "未绑定";
}

function joined(call, personId) {
  return !!call.joined?.includes(personId);
}

function callNames(call) {
  return (call.members || []).map((id) => personName(id)).join("、");
}

function openGroup(id = "") {
  const groupId = typeof id === "string" ? id : "";
  openModal({
    title: groupId ? "编辑协助分组" : "新建协助分组",
    view: GroupForm,
    props: { groupId },
  });
}

function openInvite(id) {
  openModal({
    title: "邀请成员",
    view: InviteForm,
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
  runGuarded(() => {
    const ids = session.selectedMembers.filter((id) => people().some((person) => person.id === id));
    db.startCall(ids, kind, session.station);
    toast("模拟呼叫已发起");
  });
}

function connectCall(id) {
  runGuarded(() => {
    db.updateCall(id, "connect");
    toast("模拟通话已接通");
  });
}

function endCall(id) {
  runGuarded(() => {
    db.updateCall(id, "end");
    toast("通话已结束，记录已保存");
  });
}

function muteCall(id) {
  runGuarded(() => {
    db.updateCall(id, "mute");
  });
}

function setBroadcast(value) {
  broadcastText.value = value;
  session.broadcastDraft = value;
  charCount.value = String(value).length + "/200";
}

function previewBroadcast() {
  const text = broadcastText.value.trim();
  if (!text) {
    toast("请输入广播内容", true);
    return;
  }
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

function sendBroadcast() {
  const now = Date.now();
  if (now - lastBroadcast < 1000) return;
  lastBroadcast = now;
  broadcastError.value = "";
  try {
    db.broadcast(broadcastGroupId.value, broadcastText.value);
    session.broadcastDraft = "";
    broadcastText.value = BROADCAST_DEFAULT;
    charCount.value = "最多 200 字";
    toast("广播已发送（本地模拟），回执已保存");
  } catch (error) {
    broadcastError.value = error.message || "操作失败";
  }
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
          <AppInput v-model="queryDraft" name="q" placeholder="姓名 / 安全帽编号" />
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
          <span>{{ person.name }}<small style="display:block">{{ helmetOf(person.id)?.id || "未绑定" }}</small></span>
          <AppStatus :color="helmetOf(person.id)?.online ? 'green' : 'muted'">{{ memberText(person.id) }}</AppStatus>
        </label>
      </div>
      <div class="form-actions">
        <span class="muted">已选 {{ selectedCount }} 人</span>
        <AppButton @click="startCall('单呼')">单呼</AppButton>
        <AppButton tone="primary" @click="startCall('群呼')">发起群呼</AppButton>
      </div>
    </AppPanel>
    <div class="stack">
      <AppPanel :title="'当前通话：' + (activeCall ? activeCall.kind : '未发起')">
        <template v-if="activeCall">
          <div class="call-status">
            <AppIcon :name="activeCall.status === '通话中' ? 'phone-fill' : 'phone-find-line'" />{{ "　" + activeCall.status + (activeCall.status === "通话中" ? " · 模拟接通" : " · 等待接听") }}
          </div>
          <CallVideos :call="activeCall" />
          <div v-for="personId in activeCall.members" :key="personId" class="call-member">
            <PersonAvatar :person="db.person(personId)" />
            <div>{{ personName(personId) }}{{ "　" }}<small>{{ helmetOf(personId)?.id || "未绑定" }}</small></div>
            <AppStatus :color="joined(activeCall, personId) ? 'green' : 'yellow'">{{ joined(activeCall, personId) ? "已接通（示例）" : "振铃中（示例）" }}</AppStatus>
            <AppIcon name="voiceprint-line" />
          </div>
          <div class="form-actions">
            <AppButton tone="danger" icon="phone-fill" @click="endCall(activeCall.id)">{{ activeCall.status === "正在呼叫" ? "取消呼叫" : "结束通话" }}</AppButton>
            <AppButton icon="mic-off-line" @click="muteCall(activeCall.id)">{{ activeCall.muted ? "取消静音" : "静音" }}</AppButton>
            <AppButton icon="user-add-line" @click="openInvite(activeCall.id)">邀请成员</AppButton>
          </div>
          <div v-if="activeCall.status === '正在呼叫'" class="form-actions">
            <AppButton tone="primary wide" icon="phone-line" @click="connectCall(activeCall.id)">模拟接通</AppButton>
          </div>
        </template>
        <template v-else>
          <AppEmpty text="选择人员后发起单呼或群呼" />
          <p class="note">会话状态为交互示例，通信通道兼容性待联调。</p>
        </template>
      </AppPanel>
      <AppPanel title="文字广播">
        <form class="broadcast-box" data-form="broadcast" @submit.prevent="sendBroadcast">
          <AppField label="广播对象">
            <AppSelect v-model="broadcastGroupId" name="groupId" :options="groupOptions" />
          </AppField>
          <AppTextarea name="text" maxlength="200" placeholder="请输入广播内容" :model-value="broadcastText" @update:model-value="setBroadcast" />
          <div class="char-count">{{ charCount }}</div>
          <div class="form-actions">
            <AppButton type="button" icon="play-fill" @click="previewBroadcast">试听</AppButton>
            <AppButton type="submit" tone="primary" icon="send-plane-fill">发送广播</AppButton>
          </div>
          <p v-if="broadcastError" class="form-error" role="alert">{{ broadcastError }}</p>
        </form>
      </AppPanel>
    </div>
    <div class="stack">
      <AppPanel title="最近会话">
        <template #extra><AppButton tone="plain" @click="openRecords">更多 ›</AppButton></template>
        <template v-if="recentCalls.length">
          <div v-for="call in recentCalls" :key="call.id" class="record-entry">
            <time>{{ call.time.slice(11, 16) }}</time>
            <h3><AppIcon name="user-voice-line" color="blue" />{{ "　" + call.kind + " · " + callNames(call) }}</h3>
            <p><AppStatus :color="call.status === '已结束' ? 'green' : 'yellow'">{{ call.status }}</AppStatus></p>
          </div>
        </template>
        <AppEmpty v-else text="暂无通信记录" />
      </AppPanel>
      <AppPanel title="广播记录">
        <template #extra><AppButton tone="plain" @click="openBroadcasts">更多 ›</AppButton></template>
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
