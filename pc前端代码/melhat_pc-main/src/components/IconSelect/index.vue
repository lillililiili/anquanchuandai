<template>
  <div class="icon-body">
    <el-input
      v-model="iconName"
      class="icon-search"
      clearable
      placeholder="请输入图标名称"
      @clear="filterIcons"
      @input="filterIcons"
    >
      <template #suffix><i class="el-icon-search el-input__icon" /></template>
    </el-input>
    <div class="icon-list" @scroll="handleScroll">
      <div class="list-container">
        <div v-for="(item, index) in displayList" :key="index" class="icon-item-wrapper" @click="selectedIcon(item)">
          <div :class="['icon-item', { active: activeIcon === item }]">
            <svg-icon class-name="icon" :icon-class="item" style="height: 25px;width: 16px;"/>
            <span>{{ item }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import icons from './requireIcons'

const props = defineProps({
  activeIcon: {
    type: String
  }
});

const iconName = ref('');
const emit = defineEmits(['selected']);

const pageSize = 120;
const pageNum = ref(1);
const filteredIcons = ref(icons);

const displayList = computed(() => {
  return filteredIcons.value.slice(0, pageNum.value * pageSize);
});

function handleScroll(e) {
  const { scrollTop, clientHeight, scrollHeight } = e.target;
  if (scrollTop + clientHeight >= scrollHeight - 10) {
    if (displayList.value.length < filteredIcons.value.length) {
      pageNum.value++;
    }
  }
}

function filterIcons() {
  pageNum.value = 1;
  const query = iconName.value.toLowerCase();
  filteredIcons.value = icons.filter(item => {
    return item.toLowerCase().includes(query);
  });
}

function selectedIcon(name) {
  emit('selected', name)
  document.body.click()
}

function reset() {
  iconName.value = ''
  pageNum.value = 1
  filteredIcons.value = icons
}

defineExpose({
  reset
})
</script>

<style lang='scss' scoped>
   .icon-body {
    width: 100%;
    padding: 10px;
    .icon-search {
      position: relative;
      margin-bottom: 5px;
    }
    .icon-list {
      height: 200px;
      overflow: auto;
      .list-container {
        display: flex;
        flex-wrap: wrap;
        .icon-item-wrapper {
          width: calc(100% / 3);
          height: 25px;
          line-height: 25px;
          cursor: pointer;
          display: flex;
          .icon-item {
            display: flex;
            max-width: 100%;
            height: 100%;
            padding: 0 5px;
            &:hover {
              background: var(--bg-soft);
              border-radius: 5px;
            }
            .icon {
              flex-shrink: 0;
            }
            span {
              display: inline-block;
              vertical-align: -0.15em;
              fill: currentColor;
              padding-left: 2px;
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }
          }
          .icon-item.active {
            background: var(--bg-soft);
            border-radius: 5px;
          }
        }
      }
    }
  }
</style>