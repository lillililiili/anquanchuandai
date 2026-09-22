<script setup>
import { ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import AppEmpty from "@/components/ui/AppEmpty.vue";
import AppField from "@/components/ui/AppField.vue";
import AppSelect from "@/components/ui/AppSelect.vue";
import { db } from "@/mock/runtime";
import { closeModal } from "@/stores/modal";
import { toast } from "@/stores/notify";
import { people } from "@/lib/queries";

const props = defineProps({
  callId: { type: String, default: "" },
});

const call = db.state.calls.find((item) => item.id === props.callId);
const options = people()
  .filter((person) => !call?.members.includes(person.id))
  .map((person) => [person.id, person.name]);
const personId = ref(options[0]?.[0] || "");
const error = ref("");
const saving = ref(false);

function submit() {
  if (saving.value) return;
  saving.value = true;
  error.value = "";
  try {
    db.updateCall(props.callId, "invite", personId.value);
    closeModal();
    toast("已邀请成员加入模拟通话");
  } catch (err) {
    error.value = err.message || "操作失败";
    saving.value = false;
  }
}
</script>

<template>
  <form v-if="options.length" class="form-stack" data-form="invite" :data-id="callId" @submit.prevent="submit">
    <AppField label="人员">
      <AppSelect v-model="personId" name="personId" :options="options" />
    </AppField>
    <AppButton type="submit" tone="primary">邀请加入</AppButton>
    <p class="form-error" role="alert">{{ error }}</p>
  </form>
  <AppEmpty v-else text="当前厂站人员均已在通话中" />
</template>
