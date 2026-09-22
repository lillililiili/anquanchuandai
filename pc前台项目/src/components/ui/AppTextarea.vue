<script setup>
defineProps({
  modelValue: { type: String, default: "" },
  name: { type: String, default: "" },
  placeholder: { type: String, default: "" },
  maxlength: { type: [String, Number], default: undefined },
  readonly: Boolean,
});

defineEmits(["update:modelValue"]);
</script>

<template>
  <textarea
    :name="name || undefined"
    :value="modelValue"
    :placeholder="placeholder"
    :maxlength="maxlength"
    :readonly="readonly"
    @input="$emit('update:modelValue', $event.target.value)"
  ></textarea>
</template>
