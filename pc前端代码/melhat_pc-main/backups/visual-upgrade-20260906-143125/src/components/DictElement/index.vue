<script setup lang="ts">
import { ref, onMounted, computed } from 'vue';
import { getSingleDict } from '@/utils/dict';

interface ColorMap {
  [key: number]: string;
}

const props = withDefaults(
  defineProps<{
    dict: string;
    id?: string | number;
    type?: 'tag' | 'span';
    colors?: ColorMap;
  }>(),
  {
    type: 'tag',
    id: '',
    colors: () => ({}),
  }
);

const dataOptions = ref<any[]>([]);

onMounted(() => {
  if (props.dict) {
    getSingleDict(props.dict).then((res) => {
      dataOptions.value = res;
    });
  }
});

const showArr = computed(() => {
  const idArr = props.id?.toString().split(',');

  return dataOptions.value.filter((item) => {
    return idArr?.includes(item.value);
  });
});

/**
 * 将十六进制颜色值转换为RGBA格式
 *
 * @param {string | undefined} hexColor - 十六进制颜色值，可能以#开头
 * @param {number} alpha - 透明度值，默认为1
 * @returns {string} - 返回RGBA格式的颜色值或空字符串，如果输入无效
 */
function hexToRGBA(hexColor: string | undefined, alpha = 1) {
  // 添加空值检查
  if (!hexColor) return '';

  // 去除十六进制颜色值开头可能存在的#号
  hexColor = hexColor.replace('#', '');

  // 确保颜色值是6位
  if (hexColor.length !== 6) return '';

  try {
    // 直接转换每个颜色通道
    const r = parseInt(hexColor.slice(0, 2), 16);
    const g = parseInt(hexColor.slice(2, 4), 16);
    const b = parseInt(hexColor.slice(4, 6), 16);

    // 验证转换结果是否有效
    if (isNaN(r) || isNaN(g) || isNaN(b)) return '';

    // 返回RGBA格式的颜色值
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  } catch (e) {
    // 在转换过程中捕获异常并返回空字符串
    return '';
  }
}

// 获取标签样式
const getTagStyle = (val: number | string) => {
  const color = props.colors[Number(val)];

  if (!color) return {};

  return {
    color: color,
    backgroundColor: hexToRGBA(color, 0.1),
    border: 'none',
    padding: '2px 10px',
  };
};
</script>

<template>
  <el-space>
    <template v-if="props.type === 'tag'">
      <el-tag
        v-for="(item, index) in showArr"
        :key="index"
        :style="getTagStyle(item.value)"
      >
        {{ item.label }}
      </el-tag>
    </template>
    <template v-else>
      <span v-for="(item, index) in showArr" :key="index">
        {{ item.label }}
      </span>
    </template>
  </el-space>
</template>
