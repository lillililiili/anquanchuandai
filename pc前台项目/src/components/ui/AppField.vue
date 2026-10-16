<script setup>
defineProps({
  label: { type: String, default: "" },
  vertical: Boolean,
  error: { type: String, default: "" },
});
</script>

<template>
  <label class="field" :class="{ vertical }">
    <span v-if="label || $slots.label"><slot name="label">{{ label }}</slot></span>
    <div class="field-control">
      <slot />
      <div v-if="error || $slots.hint" class="field-feedback">
        <small v-if="error" class="field-error" aria-live="polite">{{ error }}</small>
        <span v-if="$slots.hint" class="field-hint"><slot name="hint" /></span>
      </div>
    </div>
  </label>
</template>
