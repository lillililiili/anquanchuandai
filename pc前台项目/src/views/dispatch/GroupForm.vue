<script setup>
import { ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppField from "@/components/ui/AppField.vue";
import AppInput from "@/components/ui/AppInput.vue";
import MembersPicker from "@/components/domain/MembersPicker.vue";
import { db } from "@/mock/runtime";
import { session } from "@/stores/session";
import { closeModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { people } from "@/lib/queries";

const props = defineProps({
  groupId: { type: String, default: "" },
});

const found = db.state.groups.find((group) => group.id === props.groupId);
const stationIds = new Set(people().map((person) => person.id));
const name = ref(found?.name || "");
const members = ref((found?.members || []).filter((id) => stationIds.has(id)));
const error = ref("");
const saving = ref(false);

function save() {
  if (saving.value) return;
  saving.value = true;
  error.value = "";
  try {
    session.group = db.saveGroup(props.groupId || null, name.value, [...members.value], session.station);
    closeModal();
    toast("协助分组已保存");
  } catch (err) {
    error.value = err.message || "操作失败";
    saving.value = false;
  }
}
</script>

<template>
  <form class="form-stack" data-form="group" :data-id="groupId" @submit.prevent="save">
    <AppField label="分组名称">
      <AppInput v-model="name" name="name" placeholder="请输入名称" maxlength="30" required />
    </AppField>
    <MembersPicker v-model="members" />
    <div class="form-actions">
      <AppButton type="submit" tone="primary">保存分组</AppButton>
      <AppButton @click="closeModal">取消</AppButton>
    </div>
    <p class="form-error" role="alert">{{ error }}</p>
  </form>
</template>
