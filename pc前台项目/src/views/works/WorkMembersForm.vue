<script setup>
import { computed, ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppField from "@/components/ui/AppField.vue";
import AppInput from "@/components/ui/AppInput.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import MembersPicker from "@/components/domain/MembersPicker.vue";
import { db } from "@/mock/runtime";
import { closeModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { people, revision } from "@/lib/queries";

const props = defineProps({
  workId: { type: String, required: true },
});

const current = db.work(props.workId);
const members = ref(current ? [...current.members] : []);
const supervisor = ref(current?.supervisor || "");
const leader = ref(current?.leader || "");
const start = ref(current?.start || "");
const end = ref(current?.end || "");
const error = ref("");
let busy = false;
const memberOptions = computed(() => {
  revision();
  return people().map((person) => [person.id, person.name]);
});

function save() {
  if (busy) return;
  busy = true;
  error.value = "";
  try {
    const picked = new Set(members.value);
    const ordered = people()
      .map((person) => person.id)
      .filter((id) => picked.has(id));
    db.updateWork(props.workId, {
      members: ordered,
      supervisor: supervisor.value,
      leader: leader.value,
      start: start.value,
      end: end.value,
    });
    closeModal();
    toast("作业关联已更新");
  } catch (err) {
    error.value = err?.message || String(err || "操作失败");
  } finally {
    busy = false;
  }
}
</script>

<template>
  <form class="form-stack" data-form="work" :data-id="workId" @submit.prevent="save">
    <p class="note">每名人员同时只参加一项当前作业；跨作业调整需先从原作业移除。</p>
    <MembersPicker v-model="members" />
    <AppField label="监护人">
      <AppSelect v-model="supervisor" name="supervisor" :options="memberOptions" />
    </AppField>
    <AppField label="负责人">
      <AppSelect v-model="leader" name="leader" :options="memberOptions" />
    </AppField>
    <AppField label="开始时间">
      <AppInput v-model="start" name="start" type="time" required />
    </AppField>
    <AppField label="结束时间">
      <AppInput v-model="end" name="end" type="time" required />
    </AppField>
    <div class="form-actions">
      <AppButton type="submit" tone="primary">保存关联</AppButton>
      <AppButton @click="closeModal">取消</AppButton>
    </div>
    <p class="form-error">{{ error }}</p>
  </form>
</template>
