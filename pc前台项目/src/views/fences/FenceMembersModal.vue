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
  <form class="dialog-form" @submit.prevent="submit">
    <div class="dialog-form-body"><MembersPicker v-model="members" /></div>
    <div class="dialog-form-footer">
      <span>已选 {{ members.length }} 人</span>
      <AppButton @click="closeModal">取消</AppButton>
      <AppButton type="submit" tone="primary">确认成员</AppButton>
    </div>
  </form>
</template>
