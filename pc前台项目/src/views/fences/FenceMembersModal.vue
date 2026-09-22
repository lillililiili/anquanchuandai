<script setup>
import { ref } from "vue";
import AppButton from "@/components/ui/AppButton.vue";
import MembersPicker from "@/components/domain/MembersPicker.vue";
import { session } from "@/stores/session";
import { closeModal } from "@/stores/modal";

const members = ref([...(session.fenceDraft?.members || [])]);

function submit() {
  if (session.fenceDraft) session.fenceDraft.members = [...members.value];
  closeModal();
}
</script>

<template>
  <form @submit.prevent="submit">
    <MembersPicker v-model="members" />
    <div class="form-actions">
      <AppButton type="submit" tone="primary">确认成员</AppButton>
      <AppButton @click="closeModal">取消</AppButton>
    </div>
  </form>
</template>
