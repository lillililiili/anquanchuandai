<script setup lang="ts">
import { reactive, watch, ref, computed, unref } from 'vue';
import { EleDialog, EleTable } from '@/components/ElementExtra/index';
import { usePaginationTable } from '@/hooks';
import { queryDeviceTree, queryDeviceByKks } from '@/api/device/devices';
import type Node from 'element-plus/es/components/tree/src/model/node';
import { isArray } from '@/utils/is';

interface DeviceItem {
  deviceName: string;
  kks: string;
}

const props = withDefaults(
  defineProps<{
    modelValue?: string[] | string;
    deviceName?: string[] | string;
    deviceType?: string;
    disabled?: boolean;
    multiple?: boolean;
  }>(),
  {
    multiple: true,
    disabled: false,
    deviceType: '',
  }
);

const emits = defineEmits(['update:modelValue', 'update:deviceName']);

const currentParentId = ref('');

const linkData = ref(null);

const dataName = ref('');
const deviceType = ref('');

const rootLink = {
  name: '根节点',
  id: '',
};

const linkArray = computed(() => {
  const arr = [rootLink];

  function pushLink(tree) {
    if (tree.thisDevice) {
      const link = tree.thisDevice;
      arr.push({
        name: link.deviceName,
        id: link.id,
      });
      if (tree.next) {
        pushLink(tree.next);
      }
    }
  }

  if (linkData.value) {
    pushLink(linkData.value);
  }

  return arr;
});

const folderTable = usePaginationTable({
  apiFun: (params) => {
    params.deviceType = props.deviceType;

    return queryDeviceTree({ ...params, deviceType: deviceType.value }).then(
      (res) => {
        linkData.value = res.data.link;
        return res.data.page;
      }
    );
  },

  getQueryParams() {
    return {
      id: currentParentId.value,
      name: dataName.value,
      deviceType: props.deviceType,
    };
  },
});

const defaultProps = {
  children: 'children',
  label: 'deviceName',
  value: 'kks',
};

const deviceList = ref<DeviceItem[]>([]);

const echoLoading = ref(false);

watch(
  () => props.modelValue,
  (val) => {
    const newVal = getModelValue(val);

    if (newVal && newVal.length > 0) {
      // 查询并初始化
      initList(newVal);
    } else {
      if (deviceList.value.length !== 0) {
        deviceList.value = [];
      }
    }
  },
  { immediate: true }
);

function initList(kksArr: string[]) {
  const currentKKsList = deviceList.value.map((e) => e.kks);

  const equal =
    kksArr.every(function (item) {
      return currentKKsList.indexOf(item) !== -1;
    }) && kksArr.length === currentKKsList.length;

  if (equal) {
    return;
  }

  if (echoLoading.value) {
    return;
  }

  echoLoading.value = true;

  queryDeviceByKks(kksArr)
    .then((res) => {
      // console.log('queryDeviceByKks', res)
      deviceList.value = res.data;
    })
    .finally(() => {
      echoLoading.value = false;
    });
}

function getModelValue(val) {
  const v = unref(val);

  let newVal: string[];

  if (!isArray(v)) {
    if (v) {
      newVal = [v];
    } else {
      newVal = [];
    }
  } else {
    newVal = v;
  }

  return newVal;
}

watch(
  deviceList,
  (newVal) => {
    const modelKks = getModelValue(props.modelValue || []);
    const kksList = newVal.map((e) => e.kks);

    const equal =
      kksList.every(function (item) {
        return modelKks.indexOf(item) !== -1;
      }) && kksList.length === modelKks.length;

    if (!equal) {
      const names = newVal.map((e) => e.deviceName);

      if (props.multiple) {
        emits('update:modelValue', kksList);
        emits('update:deviceName', names);
      } else {
        emits('update:modelValue', kksList[0]);
        emits('update:deviceName', names[0]);
      }
    }
  },
  { deep: true }
);

const modelVisible = ref(false);

function handleClose(item: DeviceItem, index: number) {
  deviceList.value.splice(index, 1);
}

function showModal() {
  deviceType.value = props.deviceType;
  modelVisible.value = true;
  folderTable.execute();
}

function inList(item: DeviceItem) {
  return deviceList.value.find((e) => {
    return e.kks === item.kks;
  });
}

function addNode(data: DeviceItem) {
  if (props.multiple) {
    deviceList.value.push({
      deviceName: data.deviceName,
      kks: data.kks,
    });
  } else {
    deviceList.value = [
      {
        deviceName: data.deviceName,
        kks: data.kks,
      },
    ];
  }
}

function removeNode(data: DeviceItem) {
  deviceList.value = deviceList.value.filter((e) => {
    return e.kks !== data.kks;
  });
}

function onOk() {
  modelVisible.value = false;
}

function toNextLevel(row) {
  currentParentId.value = row.id;
  folderTable.execute();
}

function backPrevLevel() {
  const arr = linkArray.value;

  if (arr.length > 1) {
    goToTarget(arr[arr.length - 2]);
  }
}

const folderTree = ref();

function goToTarget(item) {
  currentParentId.value = item.id;
  folderTable.execute();
}

const handleNodeClick = (data: DeviceItem) => {
  goToTarget(data);
};

function search() {
  folderTable.execute();
}

function loadTreeNode(node: Node, resolve: (data: any[]) => void) {
  const id = node.data.id ? node.data.id : '';

  queryDeviceTree({
    id: id,
    deviceType: props.deviceType,
  }).then((res) => {
    resolve(res.data.dataList);
  });
}
</script>

<template>
  <div class="flex w-full el-input w-full">
    <div
      class="flex gap-10px device-select-wrapper el-input__wrapper w-full"
      :class="{
        'is-disabled': disabled,
      }"
      :loading="echoLoading"
    >
      <div class="flex gap-10px overflow-hidden flex-1">
        <el-tag
          v-for="(item, index) in deviceList"
          :key="index"
          :closable="!disabled"
          :disable-transitions="true"
          @close="handleClose(item, index)"
          >{{ item.deviceName }}
        </el-tag>
      </div>
      <el-button icon="Plus" link type="primary" @click="showModal" />
    </div>

    <EleDialog
      v-model="modelVisible"
      append-to-body
      :showCancel="false"
      title="选择设备"
      width="1500px"
      @ok="onOk"
    >
      <div class="flex select-dialog gap-20px">
        <el-card class="tree-wrapper w-300px">
          <div>
            <el-tree
              ref="folderTree"
              lazy
              :load="loadTreeNode"
              node-key="id"
              :props="defaultProps"
              @node-click="handleNodeClick"
            />
          </div>
        </el-card>

        <div class="folder-list flex-1 flex flex-col">
          <div class="flex flex-items-center flex-justify-between mb-6px">
            <div class="flex flex-items-center">
              <el-button icon="ArrowLeft" @click="backPrevLevel">
                返回上一级
              </el-button>

              <el-breadcrumb separator="/">
                <el-breadcrumb-item
                  v-for="(item, index) in linkArray"
                  :key="index"
                >
                  <el-button link type="primary" @click="goToTarget(item)">
                    {{ item.name }}
                  </el-button>
                </el-breadcrumb-item>
              </el-breadcrumb>
            </div>

            <div class="search-input flex gap-10px">
              <el-input
                v-model="dataName"
                placeholder="输入设备名查询"
                @keydown.enter="search"
              />
              <el-button @click="search"> 搜索 </el-button>
            </div>
          </div>
          <EleTable v-bind="folderTable.bindProps">
            <el-table-column
              label="设备名称"
              prop="deviceName"
              width="200"
              v-slot="{ row }"
            >
              <el-button link type="primary" @click="toNextLevel(row)">
                {{ row.deviceName }}
              </el-button>
            </el-table-column>
            <el-table-column label="KKS" prop="kks" width="200" />
            <el-table-column label="备注" prop="remark" width="auto" />
            <el-table-column
              label="操作"
              prop="action"
              width="200"
              v-slot="{ row }"
            >
              <el-button
                v-if="!inList(row)"
                :disabled="!row.kks || disabled"
                plain
                type="primary"
                @click="addNode(row)"
              >
                选择
              </el-button>
              <el-button
                v-else
                danger
                :disabled="disabled"
                @click="removeNode(row)"
                >移除</el-button
              >
            </el-table-column>
          </EleTable>
        </div>

        <div class="select-device w-250px flex flex-col gap-10px">
          <el-tag
            v-for="(item, index) in deviceList"
            :key="index"
            :closable="!disabled"
            :disable-transitions="false"
            @close="handleClose(item, index)"
            >{{ item.deviceName }}
          </el-tag>
        </div>
      </div>
    </EleDialog>
  </div>
</template>

<style lang="scss" scoped>
.device-select-wrapper {
  height: var(--el-input-height);
  justify-content: flex-start !important;
  flex-wrap: nowrap;
}

.device-select-wrapper.is-disabled {
  background-color: var(--el-disabled-bg-color);
  box-shadow: 0 0 0 1px var(--el-disabled-border-color) inset;
  color: var(--el-disabled-text-color);
  -webkit-text-fill-color: var(--el-disabled-text-color);
}

.select-dialog {
  .tree-wrapper {
    height: 570px;
    overflow-y: auto;
  }
  .select-device {
    border: 1px dashed var(--el-color-primary);
    border-radius: 4px;
    padding: 4px;
  }

  .select-device:empty::before {
    content: '请选择设备';
    text-align: center;
  }
}
</style>
