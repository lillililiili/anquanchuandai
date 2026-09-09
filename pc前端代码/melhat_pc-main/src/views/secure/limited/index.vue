<template>
  <div class="app-container">
    <UndeliveredNotice
      title="有限空间未交付"
      description="本页仍调用演示兼容接口，不代表现场有限空间监护已经完成。"
    />
    <el-row class="mb4" :gutter="10" :lg="6" :sm="24">
      <el-col :lg="7" :sm="24">
        <el-button icon="Plus" plain type="primary" @click="handleAdd">
          新增
        </el-button>
      </el-col>

      <el-col :lg="17" :sm="24">
        <el-form
          v-if="formVisible"
          ref="fenceRef"
          label-width="80px"
          :model="form"
          :rules="rules"
        >
          <el-form-item prop="name">
            <div class="operateInfoBox">
              <el-input
                v-model="form.name"
                class="w-200"
                clearable
                maxlength="20"
                placeholder="请输入围栏名称"
                show-word-limit
              />
              <el-tree-select
                v-model="form.deptId"
                check-strictly
                :data="deptOptions"
                placeholder="请选择负责部门"
                :props="{ value: 'id', label: 'label', children: 'children' }"
                value-key="id"
                @change="deptFind($event)"
              />
              <el-tree-select
                v-model="form.userId"
                check-strictly
                :data="staffOptions"
                placeholder="请选择负责员工"
                :props="{
                  value: 'userId',
                  label: 'nickName',
                  children: 'children',
                }"
                value-key="userId"
                @change="changeUser($event)"
              />
              <el-button plain type="primary" @click="deviceListHandle"
                >设备列表</el-button
              >
              <el-button type="primary" @click="buildArea">构建区域</el-button>
              <el-button
                icon="Edit"
                plain
                type="success"
                @click="saveDataHandle"
                >保存</el-button
              >
              <el-button @click="cancelHandle">取消</el-button>
            </div>
          </el-form-item>
        </el-form>
      </el-col>
    </el-row>
    <el-row :gutter="20">
      <el-col :lg="7" :sm="24">
        <el-table
          ref="table"
          v-loading="loading"
          :data="fenceList"
          @row-click="clickRow"
        >
          <el-table-column
            key="name"
            align="center"
            label="围栏名称"
            prop="name"
            :show-overflow-tooltip="true"
            width="auto"
          />
          <el-table-column
            key="deviceNum"
            align="center"
            label="设备"
            prop="deviceNum"
            :show-overflow-tooltip="true"
            width="100"
          />
          <el-table-column
            key="alarmFrequency"
            align="center"
            label="报警次数"
            prop="alarmFrequency"
            width="100"
          />

          <el-table-column
            align="center"
            class-name="small-padding fixed-width"
            label="操作"
            width="150"
          >
            <template #default="scope">
              <el-button
                v-hasPermi="['secure:space:edit']"
                icon="Edit"
                link
                type="primary"
                @click.stop="handleUpdate(scope.row)"
              ></el-button>
              <el-button
                v-hasPermi="['secure:space:remove']"
                icon="Delete"
                link
                type="danger"
                @click.stop="handleDelete(scope.row)"
              ></el-button>
            </template>
          </el-table-column>
        </el-table>
        <!-- fence pagination -->
        <pagination
          v-show="total > 0"
          v-model:limit="queryParams.pageSize"
          v-model:page="queryParams.pageNum"
          layout="total,prev,next"
          :total="total"
          @pagination="getList"
        />
      </el-col>
      <el-col :lg="17" :sm="24">
        <!-- map -->
        <div id="map" />
      </el-col>
    </el-row>

    <!-- device dialog -->
    <el-dialog v-model="deviceListDialog" append-to-body title="设备列表">
      <el-button @click="addDevice">添加设备</el-button>
      <el-table :data="deviceListData" style="width: 100%">
        <el-table-column
          v-for="(item, index) in columns"
          :key="index"
          :label="item.label"
          :prop="item.prop"
        >
          <template #default="{ row }">
            <el-input v-if="row.editing" v-model="row[item.prop]"></el-input>
            <span v-else>{{ row[item.prop] }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="180">
          <template #default="{ row }">
            <!-- <el-tooltip content="删除" placement="top"> -->
            <el-button
              v-if="row.editing"
              icon="Select"
              link
              type="primary"
              @click="saveRow(row)"
            ></el-button>
            <el-button
              v-if="!row.editing"
              icon="Delete"
              link
              type="danger"
              @click="deleteRow(row)"
            ></el-button>
            <el-button
              v-if="row.editing"
              icon="CloseBold"
              link
              type="info"
              @click="cancelEdit(row)"
            ></el-button>
            <!-- </el-tooltip> -->
          </template>
        </el-table-column>
      </el-table>
      <pagination
        v-show="deviceTotal > 0"
        v-model:limit="devicePageParams.pageSize"
        v-model:page="devicePageParams.pageNum"
        :total="deviceTotal"
        @pagination="getDevieList"
      />
    </el-dialog>
  </div>
</template>

<script setup name="Limited">
import { addSpace, delSpace, listSpace, updateSpace } from '@/api/secure/space';
import { deptTreeSelect } from '@/api/system/user';
import { getDepartment } from '@/api/task/schedule';
import { useMap } from '@/hooks/useMapOld';
import { removeAllDrawInstances, usePolygon } from '@/hooks/usePolygon';
import 'ol/ol.css';
import { onMounted, reactive, watch } from 'vue';

const { proxy } = getCurrentInstance();

const fenceList = ref([]);
const deviceListData = ref([]);
const deviceTempData = ref([]);
const deviceListDialog = ref(false);
const formVisible = ref(false);
const loading = ref(true);
const total = ref(0);
const deviceTotal = ref(0);
const OPERATE_TYPE = {
  add: 0,
  update: 1,
};
const currentOperateType = ref(0);
const deptOptions = ref(undefined);
const staffOptions = ref(undefined);
const polygonCoordinates = ref([]);
const isDrawing = ref(false);
const data = reactive({
  form: {},
  queryParams: {
    pageNum: 1,
    pageSize: 10,
  },
});

const rules = {
  name: { required: true, message: '请输入围栏名称' },
  deptId: { required: true, message: '请选择负责部门' },
  userId: { required: true, message: '请选择负责员工' },
};

const { queryParams, form } = toRefs(data);
const devicePage = reactive({
  devicePageParams: {
    pageNum: 1,
    pageSize: 10,
  },
});
const { devicePageParams } = toRefs(devicePage);
// device table columns
const columns = ref([
  { prop: 'deviceName', label: '设备名称' },
  { prop: 'deviceNumber', label: '设备编号' },
]);

// map
const mapRef = ref(null);

onMounted(() => {
  // init map
  const { map } = useMap(mapRef.value);
  mapRef.value = map;
});

watch(deviceListDialog, async () => {
  getDevieList();
});

/** fence list */
const getList = () => {
  loading.value = true;
  listSpace(queryParams.value).then((res) => {
    fenceList.value = res.rows;
    loading.value = false;
    total.value = res.total;
  });
};
/** device list */
const getDevieList = () => {
  if (deviceTempData.value.length) {
    const pageNum = devicePage.devicePageParams.pageNum;
    const pageSize = devicePage.devicePageParams.pageSize;
    const startIndex = (pageNum - 1) * pageSize;
    const res = deviceTempData.value.slice(startIndex, startIndex + pageSize);

    deviceListData.value = res;
    deviceTotal.value = deviceTempData.value.length;
  }
};
/** add button */
const handleAdd = () => {
  reset();
  deviceTempData.value = [];
  currentOperateType.value = 0;
  formVisible.value = true;
  stopDrawing(); // 确保在开始新的绘制之前停止之前的绘制
  initMap(mapRef.value);
  getDeptTree(); // 重新加载部门数据
};

/** update button */
const handleUpdate = async (row) => {
  reset();
  currentOperateType.value = 1;
  form.value.name = row.name;
  form.value.id = row.id;
  form.value.deptId = row.windFieldId;
  await deptFind(form.value.deptId);

  const currentUser = staffOptions.value.find(
    (item) => item.userId === row.personId
  );
  if (currentUser) {
    form.value.userId = currentUser.userId;
    // form.value.personId = currentUser.userId; // 显示名称
  } else {
    form.value.userId = row.personId;
  }

  formVisible.value = true;
  deviceTempData.value = row.deviceRelations;

  stopDrawing(); // 确保在开始新的绘制之前停止之前的绘制
  initMap(mapRef.value);

  // 回显区域
  const { drawArea } = usePolygon(mapRef.value, [row.latitudes]);
  await drawArea();
  removeAllDrawInstances();
};
/** delete button */
const handleDelete = (row) => {
  const fenceName = row.name;
  proxy.$modal
    .confirm('是否确认删除围栏名称为"' + fenceName + '"的数据项？')
    .then(function () {
      return delSpace(row.id);
    })
    .then(() => {
      getList();
      proxy.$modal.msgSuccess('删除成功');
      // 重置地图上的区域
      removeAllDrawInstances();
      initMap(mapRef.value);
      // 重置并隐藏查询区域
      reset();
    })
    .catch(() => {});
};
/** row click */
const clickRow = async (row) => {
  const { drawArea } = usePolygon(mapRef.value, [row.latitudes]);
  await drawArea();
  removeAllDrawInstances();
};

/** device list button */
const deviceListHandle = () => {
  deviceListDialog.value = true;
};
/** save data */
const saveDataHandle = () => {
  if (!form.value.name) {
    proxy.$modal.msgWarning('请输入围栏名称！');
    return;
  }

  if (OPERATE_TYPE.add === currentOperateType.value) {
    addSpace({
      name: form.value.name,
      windFieldId: form.value.deptId,
      personId: form.value.userId,
      spaceType: 0,
      latitudes: polygonCoordinates.value,
      deviceRelations: deviceListData.value,
    })
      .then(() => {
        proxy.$modal.msgSuccess('新增成功');
        formVisible.value = false;
        getList();
        stopDrawing();
        reset();
      })
      .catch((err) => {
        proxy.$modal.msgError(err.message);
      });
  }
  if (OPERATE_TYPE.update === currentOperateType.value) {
    updateSpace({
      id: form.value.id,
      name: form.value.name,
      windFieldId: form.value.deptId,
      personId: form.value.userId,
      spaceType: 0,
      latitudes: polygonCoordinates.value,
      deviceRelations: deviceListData.value,
    })
      .then(() => {
        proxy.$modal.msgSuccess('修改成功');
        formVisible.value = false;
        getList();
        stopDrawing();
        reset();
      })
      .catch((err) => {
        proxy.$modal.msgError(err.message);
      });
  }
};

/** cancel button */
const cancelHandle = () => {
  formVisible.value = false;
  stopDrawing(); // 确保在取消时停止绘制
  initMap(mapRef.value);
  reset();
};

/** draw area */
const buildArea = async () => {
  const { drawArea, toggleDrawing, onCoordinatesUpdated, drawInteraction } =
    usePolygon(mapRef.value);
  onCoordinatesUpdated((updatedCoordinates) => {
    polygonCoordinates.value = updatedCoordinates;
  });

  polygonCoordinates.value = await drawArea();

  // 移除绘制交互
  mapRef.value.removeInteraction(drawInteraction);
  toggleDrawing(false);
  isDrawing.value = false;
};
/** save row */
const saveRow = (row) => {
  row.editing = false;
};
/** delete row */
const deleteRow = (row) => {
  const index = deviceListData.value.indexOf(row);
  if (index !== -1) {
    deviceListData.value.splice(index, 1);
  }
};
/** cancel edit or delete row */
const cancelEdit = (row) => {
  const index = deviceListData.value.indexOf(row);
  if (index !== -1) {
    deviceListData.value.splice(index, 1);
  }
};
/** reset form */
const reset = () => {
  formVisible.value = false;
  proxy.resetForm('fenceRef');
  form.value = {};
  polygonCoordinates.value = [];
  staffOptions.value = []; // 清空管理员的下拉数据
};
/** init map */
const initMap = (map) => {
  let layers = map.getLayers().getArray();
  for (let i = layers.length - 1; i > 0; i--) {
    // 清除除指定图层外的其他图层
    map.removeLayer(layers[i]);
  }
};
/** department tree */
const getDeptTree = () => {
  return new Promise((resolve, reject) => {
    deptTreeSelect()
      .then((response) => {
        deptOptions.value = response.data;
        resolve();
      })
      .catch((error) => {
        reject(error);
      });
  });
};
/** query user */
const deptFind = (val) => {
  form.value.userId = '';
  return new Promise((resolve, reject) => {
    staffOptions.value = undefined;
    getDepartment(val)
      .then((response) => {
        staffOptions.value = response.data.map((user) => {
          return {
            userId: user.userId,
            nickName: user.nickName,
          };
        });
        resolve();
      })
      .catch((error) => {
        reject(error);
      });
  });
};
/** change user */
const changeUser = (val) => {
  const currentUser = staffOptions.value.find((item) => item.userId === val);
  if (currentUser) {
    form.value.userId = currentUser.userId;
    form.value.personId = currentUser.nickName; // 显示名称
  }
};
const startDrawing = () => {
  if (!isDrawing.value) {
    const { drawArea, toggleDrawing, onCoordinatesUpdated } = usePolygon(
      mapRef.value
    );
    onCoordinatesUpdated((updatedCoordinates) => {
      polygonCoordinates.value = updatedCoordinates;
    });
    drawArea().then(() => {
      toggleDrawing(true);
      isDrawing.value = true;
    });
  }
};

const stopDrawing = () => {
  if (isDrawing.value) {
    removeAllDrawInstances();
    isDrawing.value = false;
  }
};

getDeptTree();
getList();
</script>

<style lang="scss" scoped>
// .app-container {
.pagination-container {
  margin: 10px 0 20px;
  padding: 0;
  position: relative;
}

.operateInfoBox {
  display: flex;
  gap: 8px;
}

#map {
  height: 500px;
}
:deep(.el-button + .el-button) {
  margin-left: 0;
}
:deep(.el-form-item__content) {
  margin-left: 0 !important;
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
