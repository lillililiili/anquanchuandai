<template>
  <div class="check-node-wrapper">
    <template v-for="(item, index) in renderView">
      <span class="value-text" v-if="item === '_'" :key="index">{{
        valueMap[index]
      }}</span>
      <br v-else-if="item === '^'" :key="'br' + index" />
      <span v-else :key="'text' + index">{{ item }}</span>
    </template>
  </div>
</template>

<script setup>
import { ref, watch, onMounted } from "vue";

const props = defineProps({
  checkNote: {
    type: String,
    default: "",
  },
  value: {
    type: String,
    default: "",
  },
});

const emit = defineEmits(["change"]);

const valueMap = ref({});
const indexMap = ref({});
const renderView = ref([]);

const initData = () => {
  const newIndexMap = {};
  let i = 0;

  const str = props.checkNote ? props.checkNote.replace(/\n/g, "^") : "";
  const array = str.split("");

  array.forEach((element, index) => {
    if (element === "_") {
      newIndexMap[index] = i++;
    }
  });

  indexMap.value = newIndexMap;
  renderView.value = array;

  // Initialize valueMap based on props.value
  if (props.value) {
    const valueArr = props.value.split(",");
    Object.keys(newIndexMap).forEach((index) => {
      const realIndex = newIndexMap[index];
      valueMap.value[index] = valueArr[realIndex] || "";
    });
  }
};

const getValue = (index) => {
  return valueMap.value[index];
};

const setValue = (index, newValue) => {
  valueMap.value[index] = newValue;
  triggerValue();
};

const triggerValue = () => {
  const valueArray = [];
  const currentIndexMap = indexMap.value;
  Object.keys(valueMap.value).forEach((index) => {
    const realIndex = currentIndexMap[index];
    if (realIndex !== undefined) {
      valueArray[realIndex] = valueMap.value[index];
    }
  });
  emit("change", valueArray.join(","));
};

// Watchers
watch(() => props.checkNote, initData, { immediate: true });

watch(
  () => props.value,
  (newVal) => {
    if (!newVal) return;
    const valueArr = newVal.split(",");
    Object.keys(indexMap.value).forEach((index) => {
      const realIndex = indexMap.value[index];
      if (realIndex !== undefined) {
        valueMap.value[index] = valueArr[realIndex];
      }
    });
  },
  { immediate: true }
);

// Initialize data on mount
onMounted(initData);
</script>

<style lang="scss">
.check-node-wrapper {
  white-space: pre-wrap;
  line-height: 2;

  .value-text {
    padding: 2px 6px;
    border-bottom: 1px solid #e5e5e5;
  }
}
</style>
