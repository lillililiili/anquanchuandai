<template>
  <div class="app-container">
    <ModuleHeader module="fence" />
    <!-- 搜索栏 -->
    <el-form
      ref="queryRef"
      class="search-form"
      :inline="true"
      :model="queryParams"
    >
      <el-form-item label="围栏名称：" prop="fenceName">
        <el-input
          v-model="queryParams.fenceName"
          class="w-200"
          clearable
          placeholder="请输入围栏名称"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="类型：" prop="fenceType">
        <el-select
          v-model="queryParams.fenceType"
          class="w-150"
          clearable
          placeholder="全部"
        >
          <el-option
            v-for="dict in elec_fence_type"
            :key="dict.value"
            :label="dict.label"
            :value="dict.value"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="开始时间：">
        <el-date-picker
          v-model="dateRange"
          class="w-350"
          end-placeholder="结束时间"
          range-separator="至"
          start-placeholder="开始时间"
          type="datetimerange"
          value-format="YYYY-MM-DD HH:mm:ss"
        />
      </el-form-item>
      <el-form-item>
        <el-button
          class="search-primary-btn"
          :disabled="searchLoading"
          :loading="searchLoading"
          type="primary"
          @click="handleQuery"
          >搜索</el-button
        >
        <el-button class="reset-btn" @click="resetQuery">清空</el-button>
      </el-form-item>
    </el-form>

    <!-- 操作按钮 -->
    <div class="action-btn-container mb16">
      <el-button
        class="search-primary-btn"
        icon="Plus"
        type="primary"
        @click="handleAdd"
        >新增电子围栏</el-button
      >
    </div>

    <!-- 数据表格 -->
    <TableSkeleton v-if="loading && fenceList.length === 0" :columns="6" :rows="5" />
    <el-table
      v-else
      v-loading="loading && fenceList.length > 0"
      border
      class="custom-table"
      :data="fenceList"
      style="width: 100%"
    >
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
      <el-table-column align="center" label="序号" type="index" width="60" />
      <el-table-column align="center" label="围栏名称" prop="fenceName" />
      <el-table-column align="center" label="类型" prop="fenceType">
        <template #default="scope">
          <dict-tag :options="elec_fence_type" :value="scope.row.fenceType" />
        </template>
      </el-table-column>
      <el-table-column align="center" label="报警数量" prop="alertCount">
        <template #default="scope">
          <span v-if="Number(scope.row.alertCount || 0) === 0">{{
            scope.row.alertCount || 0
          }}</span>
          <span
            v-else
            class="alarm-link"
            @click="handleAlarmRecord(scope.row)"
            >{{ scope.row.alertCount }}</span
          >
        </template>
      </el-table-column>
      <el-table-column
        align="center"
        label="创建时间"
        prop="createTime"
        width="180"
      />
      <el-table-column align="center" label="状态" prop="status">
        <template #default="scope">
          <el-tag
            effect="dark"
            :type="Number(scope.row.status) === 1 ? 'success' : 'danger'"
          >
            {{ Number(scope.row.status) === 1 ? "已启用" : "已禁用" }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column align="center" label="操作" width="150">
        <template #default="scope">
          <div class="operation-icons">
            <el-tooltip content="编辑" placement="top">
              <el-button aria-label="编辑"
                icon="Edit"
                link
                type="primary"
                @click="handleUpdate(scope.row)"
              ></el-button>
            </el-tooltip>
            <el-tooltip content="删除" placement="top">
              <el-button aria-label="删除"
                icon="Delete"
                link
                type="danger"
                @click="handleDelete(scope.row)"
              ></el-button>
            </el-tooltip>
            <el-tooltip
              v-if="Number(scope.row.alertCount || 0) !== 0"
              content="报警记录"
              placement="top"
            >
              <el-button
                icon="Warning"
                link
                type="primary"
                @click="handleAlarmRecord(scope.row)"
              ></el-button>
            </el-tooltip>
          </div>
        </template>
      </el-table-column>
    </el-table>

    <!-- 分页 -->
    <div class="pg-container">
      <pagination
        v-show="total > 0"
        v-model:limit="queryParams.size"
        v-model:page="queryParams.current"
        :total="total"
        @pagination="getList"
      />
    </div>

    <!-- 报警记录弹窗 -->
    <el-dialog
      v-model="alarmVisible"
      append-to-body
      title="报警记录"
      width="900px"
    >
      <div class="alarm-dialog-content">
        <el-form
          class="alarm-search-form"
          :inline="true"
          :model="alarmQueryParams"
        >
          <el-form-item label="报警类型：">
            <el-select
              v-model="alarmQueryParams.alarmType"
              class="w-150"
              clearable
              placeholder="全部"
            >
              <el-option
                v-for="dict in alarm_type"
                :key="dict.value"
                :label="dict.label"
                :value="dict.value"
              />
            </el-select>
          </el-form-item>
          <el-form-item label="触发人员：">
            <el-input
              v-model="alarmQueryParams.userName"
              class="w-150"
              clearable
              placeholder="请输入人员姓名"
            />
          </el-form-item>
          <el-form-item label="触发时间：">
            <el-date-picker
              v-model="alarmQueryParams.startTime"
              class="w-180"
              placeholder="开始时间"
              type="datetime"
              value-format="YYYY-MM-DD HH:mm:ss"
            />
            <span class="time-separator">至</span>
            <el-date-picker
              v-model="alarmQueryParams.endTime"
              class="w-180"
              placeholder="结束时间"
              type="datetime"
              value-format="YYYY-MM-DD HH:mm:ss"
            />
          </el-form-item>
          <el-form-item>
            <el-button
              class="search-primary-btn"
              type="primary"
              @click="handleAlarmQuery"
              >搜索</el-button
            >
            <el-button class="reset-btn" @click="resetAlarmQuery"
              >清空</el-button
            >
          </el-form-item>
        </el-form>

        <el-table
          v-loading="alarmLoading"
          border
          class="alarm-table"
          :data="alarmList"
        >
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
          <el-table-column
            align="center"
            label="序号"
            type="index"
            width="60"
          />
          <el-table-column align="center" label="围栏名称" prop="fenceName" />
          <el-table-column align="center" label="告警类型" prop="alarmType">
            <template #default="scope">
              <dict-tag :options="alarm_type" :value="scope.row.alarmType" />
            </template>
          </el-table-column>
          <el-table-column align="center" label="触发人员" prop="userName" />
          <el-table-column
            align="center"
            label="触发时间"
            prop="createTime"
            width="180"
          />
          <el-table-column align="center" label="处理状态" prop="status">
            <template #default="scope">
              <el-tag
                effect="dark"
                :type="Number(scope.row.status) === 1 ? 'success' : 'danger'"
              >
                {{ Number(scope.row.status) === 1 ? "已处理" : "未处理" }}
              </el-tag>
            </template>
          </el-table-column>
        </el-table>
        <div class="pg-container mt16">
          <pagination
            v-show="alarmTotal > 0"
            v-model:limit="alarmQueryParams.size"
            v-model:page="alarmQueryParams.current"
            :total="alarmTotal"
            @pagination="getAlarmList"
          />
        </div>
      </div>
    </el-dialog>

    <!-- 新增/编辑电子围栏弹窗 -->
    <el-dialog
      v-model="dialogVisible"
      append-to-body
      class="fence-dialog"
      :title="dialogType === 'add' ? '新增电子围栏' : '编辑电子围栏'"
      width="1100px"
      @close="cancelAdd"
      @opened="handleDialogOpen"
    >
      <div v-loading="editLoading" class="fence-dialog-wrapper" element-loading-text="加载中...">
        <!-- 区块1：基础配置卡片 -->
        <div class="config-section">
          <el-form
            ref="fenceFormRef"
            class="config-form"
            inline
            :model="fenceForm"
            :rules="dialogRules"
          >
            <el-form-item
              class="form-item-name"
              label="围栏名称"
              prop="fenceName"
            >
              <el-input
                v-model="fenceForm.fenceName"
                class="input-name"
                clearable
                placeholder="请输入围栏名称"
              />
            </el-form-item>
            <el-form-item
              class="form-item-type"
              label="围栏类型"
              prop="fenceType"
            >
              <el-select
                v-model="fenceForm.fenceType"
                class="select-type"
                clearable
                placeholder="请选择围栏类型"
              >
                <el-option
                  v-for="dict in elec_fence_type"
                  :key="dict.value"
                  :label="dict.label"
                  :value="dict.value"
                />
              </el-select>
            </el-form-item>
            <el-form-item
              class="form-item-status"
              label="是否启用"
              prop="status"
              required
            >
              <el-switch
                v-model="fenceForm.status"
                :active-value="1"
                class="status-switch"
                :inactive-value="0"
              />
            </el-form-item>
          </el-form>
        </div>

        <!-- 区块2：地图绘制区 -->
        <div class="map-section">
          <div v-loading="mapLoading" class="map-container" element-loading-text="地图加载中...">
            <div id="fenceMap" class="map-box"></div>

            <!-- 悬浮绘制工具栏 -->
            <div class="map-toolbar">
              <el-button
                :class="['toolbar-btn', { drawing: isDrawing }]"
                :disabled="isDrawing"
                type="primary"
                @click="buildArea"
              >
                <el-icon class="btn-icon"><EditPen /></el-icon>
                <span>{{ isDrawing ? "绘制中..." : "绘制区域" }}</span>
              </el-button>
              <el-button
                class="toolbar-btn clear-btn"
                :disabled="polygonCoordinates.length === 0"
                @click="confirmClearArea"
              >
                <el-icon class="btn-icon"><Delete /></el-icon>
                <span>清除区域</span>
              </el-button>
            </div>

            <!-- 绘制提示 -->
            <div
              v-if="!polygonCoordinates.length && !isDrawing"
              class="map-hint"
            >
              <el-icon class="hint-icon"><InfoFilled /></el-icon>
              <span
                >点击「绘制区域」按钮，然后在地图上点击开始绘制围栏边界</span
              >
            </div>
            <div v-if="isDrawing" class="map-hint drawing-hint">
              <el-icon class="hint-icon"><Pointer /></el-icon>
              <span>点击地图添加顶点，双击完成绘制</span>
            </div>
          </div>
        </div>
      </div>

      <template #footer>
        <div class="dialog-footer-custom">
          <el-button class="footer-btn" @click="cancelAdd">取消</el-button>
          <el-button
            class="footer-btn submit-btn"
            :loading="submitLoading"
            type="primary"
            @click="submitAdd"
          >
            保存
          </el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup name="Fence">
import {
  getFencePage,
  getFenceAlarmPage,
  addFence,
  updateFence,
  getFence,
  deleteFence,
} from "@/api/fence";
import { useMap } from "@/hooks/useMap";
import { removeAllDrawInstances, usePolygon } from "@/hooks/usePolygon";
import { gcj02ToWgs84Batch, wgs84ToGcj02Batch } from "@/utils/coordTransform";
import TableSkeleton from "@/components/TableSkeleton";
import "ol/ol.css";
import { nextTick } from "vue";

const { proxy } = getCurrentInstance();
const { elec_fence_type, alarm_type } = proxy.useDict(
  "elec_fence_type",
  "alarm_type"
);

const loading = ref(false);
const searchLoading = ref(false);
const total = ref(0);
const fenceList = ref([]);
const dateRange = ref([]);

const queryParams = reactive({
  current: 1,
  size: 10,
  fenceName: "",
  fenceType: "",
  startTime: "",
  endTime: "",
});

const alarmVisible = ref(false);
const alarmTotal = ref(0);
const alarmLoading = ref(false);
const alarmList = ref([]);

const alarmQueryParams = reactive({
  current: 1,
  size: 10,
  alarmType: "",
  userName: "",
  startTime: "",
  endTime: "",
});

function getList() {
  loading.value = true;
  searchLoading.value = true;
  if (dateRange.value && dateRange.value.length === 2) {
    queryParams.startTime = dateRange.value[0];
    queryParams.endTime = dateRange.value[1];
  } else {
    queryParams.startTime = "";
    queryParams.endTime = "";
  }
  getFencePage(queryParams)
    .then((response) => {
      fenceList.value = response.data.records || response.data.rows || [];
      total.value = response.data.total || 0;
    })
    .catch(() => {
      proxy.$modal.msgError("获取围栏列表失败");
    })
    .finally(() => {
      loading.value = false;
      searchLoading.value = false;
    });
}

function handleQuery() {
  queryParams.current = 1;
  saveQueryToUrl();
  getList();
}

function resetQuery() {
  dateRange.value = [];
  proxy.resetForm("queryRef");
  clearUrlParams();
  handleQuery();
}

// 保存搜索条件到 URL 参数
function saveQueryToUrl() {
  const params = new URLSearchParams();
  if (queryParams.fenceName) params.set('fenceName', queryParams.fenceName);
  if (queryParams.fenceType) params.set('fenceType', queryParams.fenceType);
  if (dateRange.value && dateRange.value.length === 2) {
    params.set('startTime', dateRange.value[0]);
    params.set('endTime', dateRange.value[1]);
  }
  const query = params.toString()
  const hash = window.location.hash || ''
  const newUrl = query
    ? `${window.location.pathname}?${query}${hash}`
    : `${window.location.pathname}${hash}`
  window.history.replaceState(window.history.state || {}, '', newUrl)
}

// 从 URL 参数恢复搜索条件
function restoreQueryFromUrl() {
  const params = new URLSearchParams(window.location.search);
  if (params.has('fenceName')) queryParams.fenceName = params.get('fenceName');
  if (params.has('fenceType')) queryParams.fenceType = params.get('fenceType');
  if (params.has('startTime') && params.has('endTime')) {
    dateRange.value = [params.get('startTime'), params.get('endTime')];
  }
}

// 清除 URL 参数
function clearUrlParams() {
  window.history.replaceState(window.history.state || {}, '', window.location.pathname + (window.location.hash || ''))
}

// ============== 新增/编辑围栏相关 ==================
const dialogVisible = ref(false);
const dialogType = ref("add");
const submitLoading = ref(false);
const fenceFormRef = ref(null);
const fenceForm = ref({
  id: null,
  fenceName: "",
  fenceType: "",
  status: 1,
});
const dialogRules = {
  fenceName: [{ required: true, message: "请输入围栏名称", trigger: "blur" }],
  fenceType: [{ required: true, message: "请选择围栏类型", trigger: "change" }],
};

const mapRef = ref(null);
const isDrawing = ref(false);
const polygonCoordinates = ref([]);
const mapLoading = ref(false);
const mapInitialized = ref(false);
const editLoading = ref(false);
const pendingEditCoordinates = ref(null); // 存储待渲染的编辑坐标
let polygonCleanup = null; // 存储清理函数

const resetMapLayer = () => {
  if (!mapRef.value) return;
  // 调用清理函数移除事件监听器和交互
  if (polygonCleanup) {
    polygonCleanup();
    polygonCleanup = null;
  }
  removeAllDrawInstances();
  // 清除围栏区域图层
  mapRef.value.getLayers().forEach((layer) => {
    if (layer.get("name") === "areaLayer") {
      const source = layer.getSource();
      if (source) source.clear();
    }
  });
  // 清除轨迹图层（避免显示从其他页面遗留的轨迹）
  const mapHook = useMap();
  if (mapHook.clearTrack) {
    mapHook.clearTrack();
  }
};

const handleDialogOpen = () => {
  if (!mapInitialized.value) {
    mapLoading.value = true;
  }

  nextTick(() => {
    if (!mapRef.value) {
      const mapHook = useMap();
      mapHook.initMap("fenceMap");
      mapRef.value = mapHook.map.value;
      mapInitialized.value = true;
    } else {
      mapRef.value.updateSize();
    }

    if (mapLoading.value) {
      setTimeout(() => {
        mapLoading.value = false;
      }, 300);
    }

    resetMapLayer();

    // 新增模式：渲染已有坐标
    if (dialogType.value === "add" && polygonCoordinates.value.length > 0) {
      setTimeout(() => {
        mapRef.value?.updateSize();
        const result = usePolygon(mapRef.value, [polygonCoordinates.value]);
        polygonCleanup = result.cleanup;
      }, 300);
    }

    // 编辑模式：渲染待处理的坐标
    if (dialogType.value === "edit" && pendingEditCoordinates.value) {
      setTimeout(() => {
        mapRef.value?.updateSize();
        polygonCoordinates.value = pendingEditCoordinates.value;
        const result = usePolygon(mapRef.value, [polygonCoordinates.value]);
        polygonCleanup = result.cleanup;
        pendingEditCoordinates.value = null;
      }, 300);
    }
  });
};

const buildArea = async () => {
  if (!mapRef.value) return;
  isDrawing.value = true;
  resetMapLayer();
  const { drawArea, toggleDrawing, onCoordinatesUpdated, cleanup } = usePolygon(
    mapRef.value
  );
  polygonCleanup = cleanup;

  onCoordinatesUpdated((updatedCoordinates) => {
    polygonCoordinates.value = updatedCoordinates;
  });

  polygonCoordinates.value = await drawArea();

  toggleDrawing(false);
  isDrawing.value = false;
};

const clearArea = () => {
  if (!mapRef.value) return;
  resetMapLayer();
  polygonCoordinates.value = [];
  isDrawing.value = false;
};

const confirmClearArea = () => {
  if (polygonCoordinates.value.length === 0) return;

  proxy.$modal.confirm('确定要清除已绘制的区域吗？').then(() => {
    clearArea();
  }).catch(() => {});
};

function handleAdd() {
  dialogType.value = "add";
  dialogVisible.value = true;
  fenceForm.value = {
    id: null,
    fenceName: "",
    fenceType: "",
    status: 1,
  };
  polygonCoordinates.value = [];
  isDrawing.value = false;
  // 清除校验状态
  nextTick(() => {
    if (fenceFormRef.value) {
      fenceFormRef.value.clearValidate();
    }
  });
}

function cancelAdd() {
  dialogVisible.value = false;
  submitLoading.value = false;
  pendingEditCoordinates.value = null;
  if (fenceFormRef.value) {
    fenceFormRef.value.resetFields();
  }
  clearArea();
}

function submitAdd() {
  if (!fenceFormRef.value) return;
  fenceFormRef.value.validate((valid) => {
    if (!valid) return;
    if (polygonCoordinates.value.length === 0) {
      proxy.$modal.msgWarning("请绘制区域范围！");
      return;
    }

    let flatCoords = [];
    if (
      Array.isArray(polygonCoordinates.value[0]) &&
      Array.isArray(polygonCoordinates.value[0][0])
    ) {
      flatCoords = polygonCoordinates.value[0];
    } else if (Array.isArray(polygonCoordinates.value[0])) {
      flatCoords = polygonCoordinates.value;
    }

    // 将地图上的 GCJ-02 坐标转换为 WGS84 坐标后保存
    const wgs84Coords = gcj02ToWgs84Batch(flatCoords);
    const coordinatesPayload = wgs84Coords.map((coord) => ({
      longitude: coord[0],
      latitude: coord[1],
    }));

    const payload = {
      coordinates: coordinatesPayload,
      fence: {
        fenceName: fenceForm.value.fenceName,
        fenceType: fenceForm.value.fenceType,
        status: fenceForm.value.status,
      },
    };

    submitLoading.value = true;

    const apiCall =
      dialogType.value === "edit"
        ? updateFence({
            ...payload,
            fence: { ...payload.fence, id: fenceForm.value.id },
          })
        : addFence(payload);

    apiCall
      .then(() => {
        proxy.$modal.msgSuccess(
          dialogType.value === "edit" ? "修改成功" : "新增成功"
        );
        dialogVisible.value = false;
        submitLoading.value = false;
        getList();
        clearArea();
      })
      .catch(() => {
        submitLoading.value = false;
        proxy.$modal.msgError(
          dialogType.value === "edit" ? "修改失败，请重试" : "新增失败，请重试"
        );
      });
  });
}
// ===========================================

function handleUpdate(row) {
  dialogType.value = "edit";
  editLoading.value = true;
  dialogVisible.value = true;
  // 先清空坐标和待处理坐标，避免显示旧数据
  polygonCoordinates.value = [];
  pendingEditCoordinates.value = null;

  getFence(row.id)
    .then((res) => {
      const data = res.data || {};
      const fenceData = data.fence || data || {};
      const coordsData = data.coordinates || [];

      fenceForm.value = {
        id: fenceData.id || row.id,
        fenceName: fenceData.fenceName || row.fenceName || "",
        fenceType: fenceData.fenceType || row.fenceType || "",
        status:
          fenceData.status !== undefined && fenceData.status !== null
            ? Number(fenceData.status)
            : row.status !== undefined && row.status !== null
            ? Number(row.status)
            : 1,
      };

      if (coordsData.length > 0) {
        const wgs84Coords = coordsData.map((c) => [c.longitude, c.latitude]);
        // 将坐标存入 pendingEditCoordinates，由 handleDialogOpen 在 resetMapLayer 之后统一渲染
        pendingEditCoordinates.value = wgs84ToGcj02Batch(wgs84Coords);
      } else {
        pendingEditCoordinates.value = null;
      }

      isDrawing.value = false;
      nextTick(() => {
        if (fenceFormRef.value) {
          fenceFormRef.value.clearValidate();
        }
      });
    })
    .catch(() => {
      dialogVisible.value = false;
      proxy.$modal.msgError("获取围栏详情失败");
    })
    .finally(() => {
      editLoading.value = false;
    });
}

function handleDelete(row) {
  proxy.$modal
    .confirm("是否确认删除该围栏数据项？")
    .then(function () {
      return deleteFence(row.id);
    })
    .then(() => {
      getList();
      proxy.$modal.msgSuccess("删除成功");
    })
    .catch((err) => {
      if (err !== 'cancel' && err !== 'close') {
        proxy.$modal.msgError("删除失败，请重试");
      }
    });
}

function handleAlarmRecord(row) {
  if (Number(row.alertCount || 0) === 0) {
    return;
  }
  alarmVisible.value = true;
  handleAlarmQuery();
}

function getAlarmList() {
  alarmLoading.value = true;
  getFenceAlarmPage(alarmQueryParams)
    .then((response) => {
      alarmList.value = response.data.records || response.data.rows || [];
      alarmTotal.value = response.data.total || 0;
    })
    .catch(() => {
      proxy.$modal.msgError("获取报警记录失败");
    })
    .finally(() => {
      alarmLoading.value = false;
    });
}

function handleAlarmQuery() {
  alarmQueryParams.current = 1;
  getAlarmList();
}

function resetAlarmQuery() {
  alarmQueryParams.startTime = "";
  alarmQueryParams.endTime = "";
  alarmQueryParams.alarmType = "";
  alarmQueryParams.userName = "";
  handleAlarmQuery();
}

onMounted(() => {
  restoreQueryFromUrl();
  getList();
});
</script>

<style scoped lang="scss">
.app-container {
  padding: 8px 24px 24px;
  min-height: calc(100vh - 60px);
}

.search-form {
  background: var(--bg-pure);
  padding: 20px;
  border-radius: 8px;
  margin-bottom: 16px;
  box-shadow: var(--shadow-sm);

  :deep(.el-form-item) {
    margin-bottom: 0;
    margin-right: 24px;

    .el-form-item__label {
      font-weight: 500;
      color: var(--text-secondary);
    }
  }
}

.time-separator {
  margin: 0 8px;
  color: var(--text-secondary);
}

.search-primary-btn {
  background-color: var(--color-action);
  border-color: var(--color-action);
  &:hover,
  &:focus {
    background-color: var(--color-action-hover);
    border-color: var(--color-action-hover);
  }
}

.reset-btn {
  color: var(--text-secondary);
  border-color: var(--border-color);
  &:hover {
    color: var(--text-primary);
    border-color: var(--border-hover);
    background-color: var(--bg-soft);
  }
}

.custom-table {
  border-radius: 8px;
  overflow: hidden;
  box-shadow: var(--shadow-sm);

  :deep(.el-table__header-wrapper th) {
    background-color: var(--bg-table-header);
    color: var(--text-primary);
    font-weight: 600;
    height: 50px;
  }

  :deep(.el-table__row) {
    height: 60px;
  }
}

.alarm-link {
  color: var(--color-danger);
  cursor: pointer;
  text-decoration: underline;
  font-weight: 500;
}

.operation-icons {
  display: flex;
  justify-content: center;
  gap: 12px;

  .el-button {
    padding: 0;
    font-size: 18px;
  }
}

.pg-container {
  display: flex;
  justify-content: flex-end;
  margin-top: 20px;
}

.alarm-dialog-content {
  padding: 0 10px 20px;
}

.alarm-search-form {
  margin-bottom: 20px;
  :deep(.el-form-item) {
    margin-bottom: 12px;
  }
}

.alarm-table {
  :deep(.el-table__header-wrapper th) {
    background-color: var(--bg-table-header);
  }
}

.mt16 {
  margin-top: 16px;
}

.mb16 {
  margin-bottom: 16px;
}

.fence-dialog-wrapper {
  padding: 0;
}

// 弹窗整体样式
.fence-dialog {
  :deep(.el-dialog__header) {
    border-bottom: 1px solid var(--border-color);
    padding: 16px 24px;
    margin-right: 0;

    .el-dialog__title {
      font-size: 18px;
      font-weight: 600;
      color: var(--text-primary);
    }
  }

  :deep(.el-dialog__body) {
    padding: 20px 24px;
  }

  :deep(.el-dialog__footer) {
    border-top: 1px solid var(--border-color);
    padding: 16px 24px;
  }
}

// 区块通用样式
.config-section,
.map-section,
.info-section,
.empty-info-section {
  &:last-child {
    margin-bottom: 0;
  }
}

// 基础配置区样式
.config-section {
  padding: 0 0 16px 0;

  .config-form {
    display: grid;
    align-items: center;
    gap: 18px;

    :deep(.el-form-item) {
      margin-bottom: 0;
      margin-right: 0;
      flex: 1;

      .el-form-item__label {
        font-weight: 500;
        color: var(--text-secondary);
      }
    }

    .form-item-name {
      flex: 1.2;
      min-width: 200px;

      .input-name {
        width: 100%;
      }
    }

    .form-item-type {
      flex: 0.8;
      min-width: 160px;

      :deep(.select-type) {
        width: 100%;

        // 覆盖 Element Plus 下拉框聚焦边框颜色
        .el-input__wrapper {
          box-shadow: 0 0 0 1px var(--border-color) inset !important;
        }

        // 聚焦状态
        &.is-focus .el-input__wrapper,
        .el-input.is-focus .el-input__wrapper,
        .el-input__wrapper.is-focus,
        .el-input__wrapper:focus {
          box-shadow: 0 0 0 1px var(--brand-primary) inset !important;
        }

        // 悬停状态
        &:hover .el-input__wrapper,
        &.is-hover .el-input__wrapper {
          box-shadow: 0 0 0 1px var(--brand-primary) inset !important;
        }
      }
    }

    .form-item-status {
      flex: 0.5;
      min-width: 100px;

      .status-switch {
        :deep(.el-switch__core) {
          width: 44px;
          height: 22px;
          border-radius: 11px;

          .el-switch__action {
            width: 18px;
            height: 18px;
          }
        }
      }
    }
  }
}

// 地图区样式
.map-section {
  .map-container {
    position: relative;
    border-radius: 12px;
    overflow: hidden;

    .map-box {
      width: 100%;
      height: 450px;
      background: var(--bg-muted);
    }

    // 悬浮工具栏
    .map-toolbar {
      position: absolute;
      top: 16px;
      right: 16px;
      display: flex;
      gap: 12px;
      z-index: 10;

      .toolbar-btn {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 10px 16px;
        font-size: 14px;
        border-radius: 8px;
        box-shadow: var(--shadow-sm);
        transition: all 0.3s ease;

        &.drawing {
          animation: pulse 1.5s ease-in-out infinite;
        }

        .btn-icon {
          font-size: 16px;
        }

        &:hover:not(:disabled) {
          transform: translateY(-2px);
          box-shadow: var(--shadow-md);
        }
      }

      .clear-btn {
        background: var(--bg-pure);
        border-color: var(--border-color);
        color: var(--text-secondary);

        &:hover:not(:disabled) {
          color: var(--color-danger);
          border-color: var(--color-danger);
        }
      }
    }

    // 绘制提示
    .map-hint {
      position: absolute;
      bottom: 16px;
      left: 50%;
      transform: translateX(-50%);
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 12px 20px;
      background: var(--bg-pure);
      border-radius: 8px;
      box-shadow: var(--shadow-sm);
      font-size: 13px;
      color: var(--text-secondary);
      z-index: 10;

      .hint-icon {
        font-size: 16px;
        color: var(--text-muted);
      }

      &.drawing-hint {
        background: var(--color-primary);
        color: var(--color-action-foreground);
        animation: slideUp 0.3s ease;

        .hint-icon {
          color: var(--color-action-foreground);
        }
      }
    }
  }
}

// 底部操作栏样式
.dialog-footer-custom {
  display: flex;
  justify-content: flex-end;
  gap: 12px;

  .footer-btn {
    padding: 10px 24px;
    font-size: 14px;
    border-radius: 8px;
    transition: all 0.3s ease;

    &:hover {
      transform: translateY(-1px);
    }
  }

  .submit-btn {
    display: flex;
    align-items: center;
    gap: 6px;
    background: var(--color-action);
    border: none;
    box-shadow: var(--shadow-glow);

    &:hover {
      background: var(--color-action-hover);
      box-shadow: var(--shadow-md);
    }

    .btn-icon {
      font-size: 16px;
    }
  }
}

// 动画
@keyframes pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 var(--shadow-glow);
  }
  50% {
    box-shadow: 0 0 0 4px transparent;
  }
}

@keyframes slideUp {
  from {
    opacity: 0;
    transform: translateX(-50%) translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateX(-50%) translateY(0);
  }
}

// 响应式调整
@media (max-width: 768px) {
  .config-section {
    .config-form {
      flex-direction: column;

      .form-item-name,
      .form-item-type {
        flex: 1;
        min-width: auto;
      }
    }
  }

  .info-section {
    .info-cards {
      grid-template-columns: 1fr;
    }
  }

  .map-section {
    .map-container {
      .map-box {
        height: 350px;
      }

      .map-toolbar {
        flex-direction: column;
        top: auto;
        bottom: 60px;
        right: 12px;
      }
    }
  }
}
</style>
