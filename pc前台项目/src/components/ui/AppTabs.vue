<script setup>
defineProps({
  modelValue: { type: String, default: "" },
  tabs: { type: Array, default: () => [] },
  box: Boolean,
});

defineEmits(["update:modelValue"]);
</script>

<template>
  <div :class="['tabs', box ? 'box' : '']">
    <button
      v-for="tab in tabs"
      :key="tab.id"
      type="button"
      :class="['btn', modelValue === tab.id ? 'active' : '']"
      @click="$emit('update:modelValue', tab.id)"
    >
      {{ tab.label }}
    </button>
  </div>
</template>
