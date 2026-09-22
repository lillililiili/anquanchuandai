<script setup>
defineProps({
  person: { type: Object, default: null },
  photo: Boolean,
});
</script>

<template>
  <img v-if="photo" class="avatar photo" src="/assets/avatar.png" :alt="person?.name || '人员'" />
  <span v-else class="avatar">{{ person?.name?.slice(0, 1) || "人" }}</span>
</template>
