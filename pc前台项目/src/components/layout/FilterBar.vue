<script setup>
import AppButton from "@/components/ui/AppButton.vue";

defineEmits(["submit", "reset"]);
</script>

<template>
  <form class="filters" @submit.prevent="$emit('submit')">
    <slot />
    <AppButton type="submit" tone="primary" icon="search-line">查询</AppButton>
    <AppButton icon="refresh-line" @click="$emit('reset')">重置</AppButton>
  </form>
</template>
