<script setup>
import { computed } from "vue";

const props = defineProps({
  modelValue: { type: [String, Number], default: "" },
  options: { type: Array, default: () => [] },
  name: { type: String, default: "" },
  disabled: Boolean,
  ariaLabel: { type: String, default: "" },
});

defineEmits(["update:modelValue"]);

const normalized = computed(() =>
  props.options.map((option) => {
    if (Array.isArray(option)) return { value: option[0], label: option[1] };
    if (option && typeof option === "object") return { value: option.value, label: option.label };
    return { value: option, label: option };
  }),
);
</script>

<template>
  <select
    :name="name || undefined"
    :value="modelValue"
    :disabled="disabled"
    :aria-label="ariaLabel || undefined"
    @change="$emit('update:modelValue', $event.target.value)"
  >
    <option v-for="option in normalized" :key="String(option.value)" :value="option.value">{{ option.label }}</option>
  </select>
</template>
