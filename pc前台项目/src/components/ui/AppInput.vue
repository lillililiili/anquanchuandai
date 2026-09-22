<script setup>
defineProps({
  modelValue: { type: [String, Number], default: "" },
  type: { type: String, default: "text" },
  name: { type: String, default: "" },
  placeholder: { type: String, default: "" },
  maxlength: { type: [String, Number], default: undefined },
  required: Boolean,
  disabled: Boolean,
  readonly: Boolean,
  autocomplete: { type: String, default: undefined },
  ariaLabel: { type: String, default: "" },
});

defineEmits(["update:modelValue"]);
</script>

<template>
  <input
    :type="type"
    :name="name || undefined"
    :value="modelValue"
    :placeholder="placeholder"
    :maxlength="maxlength"
    :required="required"
    :disabled="disabled"
    :readonly="readonly"
    :autocomplete="autocomplete"
    :aria-label="ariaLabel || undefined"
    @input="$emit('update:modelValue', $event.target.value)"
  />
</template>
