<script setup>
import { computed } from "vue";

const props = defineProps({
  name: { type: String, required: true },
  color: { type: String, default: "" },
});

const iconName = computed(() =>
  props.name.startsWith("alarm-warning") ? props.name.replace("alarm-warning", "alert") : props.name,
);
</script>

<template>
  <i :class="['ri-' + iconName, color]" aria-hidden="true"></i>
</template>
