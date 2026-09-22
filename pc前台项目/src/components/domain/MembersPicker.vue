<script setup>
import AppEmpty from "@/components/ui/AppEmpty.vue";
import { people } from "@/lib/queries";
import { tick } from "@/mock/runtime";
import { computed } from "vue";

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
});

const emit = defineEmits(["update:modelValue"]);
const list = computed(() => {
  tick.value;
  return people();
});

function toggle(id, checked) {
  const next = new Set(props.modelValue);
  if (checked) next.add(id);
  else next.delete(id);
  emit("update:modelValue", [...next]);
}
</script>

<template>
  <div class="check-grid">
    <label v-for="person in list" :key="person.id">
      <input type="checkbox" name="members" :value="person.id" :checked="modelValue.includes(person.id)" @change="toggle(person.id, $event.target.checked)" />
      {{ person.name }} <small>{{ person.team }}</small>
    </label>
    <AppEmpty v-if="!list.length" text="当前厂站暂无人员" />
  </div>
</template>
