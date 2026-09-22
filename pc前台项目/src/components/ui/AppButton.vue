<script setup>
import AppIcon from "./AppIcon.vue";

defineProps({
  type: { type: String, default: "button" },
  tone: { type: String, default: "" },
  icon: { type: String, default: "" },
  disabled: Boolean,
  ariaLabel: { type: String, default: "" },
});

defineEmits(["click"]);
</script>

<template>
  <button
    :type="type"
    :class="['btn', tone]"
    :disabled="disabled"
    :aria-label="ariaLabel || undefined"
    @click="$emit('click', $event)"
  >
    <AppIcon v-if="icon" :name="icon" />
    <slot />
  </button>
</template>
