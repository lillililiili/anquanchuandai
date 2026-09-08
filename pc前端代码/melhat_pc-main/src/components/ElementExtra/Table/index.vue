<script setup lang="ts">
import { ref, computed, watch } from "vue";
import { ElTable, ElPagination } from "element-plus";

const props = withDefaults(
  defineProps<{
    data?: any[];
    columns?: any[];
    pagination?: any;
    loading?: boolean;
    selection?: boolean;
    selectRows?: any[];
    rowKey?: string | Function;
    checkEnable?: (row: any) => boolean;
  }>(),
  {
    pagination: {
      background: true,
      layout: "prev,pager,next,sizes,total",
      total: 0,
    },
  }
);

const emit = defineEmits(["change", "update:selectRows"]);

const currentPage = computed({
  get() {
    return props.pagination.currentPage;
  },
  set(val) {
    emit("change", {
      currentPage: val,
      pageSize: pageSize.value,
    });
  },
});

const pageSize = computed({
  get() {
    return props.pagination.pageSize;
  },
  set(val) {
    emit("change", {
      currentPage: 1,
      pageSize: val,
    });
  },
});

const tableRef = ref();

defineExpose({
  getTable() {
    return tableRef.value;
  },
});

const selectValue = ref([]);

watch(
  () => props.selectRows,
  (val) => {
    selectValue.value = val || [];
  },
  {
    immediate: true,
  }
);

function onCheckBoxChange(check, row, index) {
  if (!props.rowKey) {
    console.warn("请传入rowKey属性");
    return false;
  }
  const getRowKey = getRowKeyFun();

  if (check) {
    selectValue.value.push(row);
  } else {
    const checkId = getRowKey(row);
    const findIndex = selectValue.value.findIndex((e) => {
      return getRowKey(e) === checkId;
    });
    selectValue.value.splice(findIndex, 1);
  }
  emit("update:selectRows", selectValue.value);
}

const getRowKeyFun = () => {
  if (typeof props.rowKey === "string") {
    return (row) => {
      return row[props.rowKey as string];
    };
  } else {
    return props.rowKey;
  }
};

const onSelectAll = (selection: any[]) => {
  if (!props.rowKey) {
    console.warn("请传入rowKey属性");
    return false;
  }
  const getRowKey = getRowKeyFun();

  // console.log("selection", selection);
  if (selection && selection.length > 0) {
    const ids = selectValue.value.map((row) => {
      return getRowKey(row);
    });
    selection.forEach((e) => {
      const eid = getRowKey(e);

      if (ids.includes(eid)) {
        return;
      }

      if (isDisabled(e)) {
        return;
      }

      selectValue.value.push(e);
    });
  } else {
    const ids = props.data.map((row) => {
      return getRowKey(row);
    });
    selectValue.value = selectValue.value.filter((row) => {
      const currentId = getRowKey(row);
      return !ids.includes(currentId);
    });
  }
  emit("update:selectRows", selectValue.value);
};

function isChecked(row) {
  if (!props.rowKey) {
    console.warn("请传入rowKey属性");
    return false;
  }

  const getRowKey = getRowKeyFun();

  const targetId = getRowKey(row);

  return (
    selectValue.value.findIndex((item) => {
      if (typeof props.rowKey === "string") {
        return item[props.rowKey] === targetId;
      } else {
        return props.rowKey(item) === targetId;
      }
    }) > -1
  );
}

const isDisabled = (row: any) => {
  if (props.checkEnable) {
    return props.checkEnable(row);
  }
  return false;
};
</script>

<template>
  <div v-loading="props.loading" class="col">
    <ElTable
      ref="tableRef"
      border
      v-bind="$attrs"
      class="w-100% flex-self-center"
      :data="props.data"
      stripe
      @select-all="onSelectAll"
    >
      <el-table-column v-if="selection" type="selection" width="55">
        <template #default="{ row, $index }">
          <el-checkbox
            :modelValue="isChecked(row)"
            size="large"
            :disabled="isDisabled(row)"
            @change="onCheckBoxChange($event, row, $index)"
          />
        </template>
      </el-table-column>
      <slot />
    </ElTable>
    <ElPagination
      v-model:current-page="currentPage"
      v-model:page-size="pageSize"
      :background="props.pagination.background"
      class="flex-self-end mt-10px"
      :layout="props.pagination.layout"
      :total="props.pagination.total"
    ></ElPagination>
  </div>
</template>

<style lang="less" scoped></style>
