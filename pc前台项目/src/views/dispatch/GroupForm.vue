<script setup>
import { ref } from "vue";
import { useFieldErrors } from "@ui-spec/useFieldErrors";
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
const { formRef, errors, validate } = useFieldErrors(() => ({ name: name.value, members: members.value }));

function save() {
  if (saving.value) return;
  if (!validate({ name: !name.value.trim() ? '请填写分组名称' : name.value.length > 30 ? '分组名称最多30字' : '', members: !members.value.length && '请选择成员' })) return;
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
  <form ref="formRef" novalidate class="form-stack dialog-form" data-form="group" :data-id="groupId" @submit.prevent="save">
    <div class="dialog-form-body">
    <AppField label="分组名称" data-field="name" :error="errors.name">
      <AppInput v-model="name" name="name" placeholder="请输入名称" maxlength="30" required />
    </AppField>
    <div data-field="members"><p class="dialog-group-label">分组成员 · 已选 {{ members.length }} 人</p><MembersPicker v-model="members" /><small v-if="errors.members" class="field-error" aria-live="polite">{{ errors.members }}</small></div>
    <p v-if="error" class="form-error" role="alert">{{ error }}</p>
    </div>
    <div class="dialog-form-footer">
      <AppButton :disabled="saving" @click="closeModal">取消</AppButton>
      <AppButton type="submit" tone="primary" :disabled="saving">保存分组</AppButton>
    </div>
  </form>
</template>
