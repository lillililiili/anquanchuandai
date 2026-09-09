<template>
  <div class="app-container">
    <ModuleHeader module="sos" />
    <!-- 头部搜索 -->
    <el-form
      v-show="showSearch"
      ref="queryRef"
      class="search-form"
      :inline="true"
      :model="queryParams"
    >
      <el-form-item label="报警类型：" prop="alarmType">
        <el-select
          v-model="queryParams.alarmType"
          class="w-180"
          clearable
          placeholder="全部"
        >
          <el-option label="全部" value="" />
          <el-option
            v-for="dict in alarm_type"
            :key="dict.value"
            :label="dict.label"
            :value="dict.value"
          />
        </el-select>
      </el-form-item>
      <el-form-item label="报警人：" prop="userName">
        <el-input
          v-model="queryParams.userName"
          class="w-180"
          clearable
          placeholder="请输入报警人姓名"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="开始时间：" prop="startTimeFrom">
        <el-date-picker
          v-model="queryParams.startTimeFrom"
          class="w-200"
          placeholder="开始时间"
          type="datetime"
          value-format="YYYY-MM-DD HH:mm:ss"
        />
      </el-form-item>
      <el-form-item label="至" label-width="36px" style="margin-right: 16px">
        <el-date-picker
          v-model="queryParams.startTimeTo"
          class="w-200"
          placeholder="结束时间"
          type="datetime"
          value-format="YYYY-MM-DD HH:mm:ss"
        />
      </el-form-item>
      <el-form-item>
        <el-button class="search-btn" :disabled="searchLoading" icon="Search" :loading="searchLoading" type="primary" @click="handleQuery"
          >搜索</el-button
        >
        <el-button class="reset-btn" icon="Refresh" @click="resetQuery">清空</el-button>
      </el-form-item>
    </el-form>

    <!-- Tab 切换 -->
    <div class="tab-container">
      <el-button-group>
        <el-button
          :class="['tab-btn', activeTab === 0 ? 'active' : '']"
          :type="activeTab === 0 ? 'info' : 'default'"
          @click="handleTabChange(0)"
        >未处理</el-button>
        <el-button
          :class="['tab-btn', activeTab === 1 ? 'active' : '']"
          :type="activeTab === 1 ? 'info' : 'default'"
          @click="handleTabChange(1)"
        >已处理</el-button>
      </el-button-group>
    </div>

    <!-- 数据表格 -->
    <TableSkeleton v-if="loading && alarmList.length === 0" :columns="6" :rows="5" />
    <el-table
      v-else
      v-loading="loading && alarmList.length > 0"
      class="custom-table"
      :data="alarmList"
      style="width: 100%"
    >
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
      <el-table-column align="center" label="序号" type="index" width="65" />
      
      <!-- 未处理列 -->
      <template v-if="activeTab === 0">
        <el-table-column align="center" label="报警类型" prop="alarmType">
          <template #default="scope">
            <el-tag effect="light" size="small" :type="getAlarmLevelType(scope.row.alarmLevel)">
              <dict-tag plain :options="alarm_type" :value="scope.row.alarmType" />
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column align="center" label="报警人" prop="userName" />
        <el-table-column align="center" label="报警设备号" prop="hatNumber" />
        <el-table-column align="center" label="呼叫时间" min-width="160" prop="alarmStartTime" />
      </template>

      <!-- 已处理列 -->
      <template v-else>
        <el-table-column align="center" label="报警类型" prop="alarmType">
          <template #default="scope">
            <el-tag effect="light" size="small" :type="getAlarmLevelType(scope.row.alarmLevel)">
              <dict-tag plain :options="alarm_type" :value="scope.row.alarmType" />
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column align="center" label="呼叫人" prop="userName" />
        <el-table-column align="center" label="呼叫设备号" prop="hatNumber" />
        <el-table-column align="center" label="呼叫时间" min-width="160" prop="alarmStartTime" />
        <el-table-column align="center" label="结束时间" min-width="160" prop="alarmEndTime" />
        <el-table-column align="center" label="事件说明" prop="description" show-overflow-tooltip />
      </template>

      <el-table-column align="center" label="操作" :width="activeTab === 0 ? 180 : 120">
        <template #default="scope">
          <div class="operation-buttons">
            <template v-if="activeTab === 0">
              <el-tooltip content="详情" placement="top">
                <el-button aria-label="详情" icon="View" link type="primary" @click="handleDetail(scope.row)"></el-button>
              </el-tooltip>
              <el-tooltip v-if="scope.row.alarmType === 'SOS告警'" content="接听能力未完成，真实通话在 S7 交付" placement="top">
                <el-button disabled icon="Phone" link type="primary" @click="handleAnswer(scope.row)"></el-button>
              </el-tooltip>
              <el-tooltip content="处理" placement="top">
                <el-button aria-label="处理" icon="CircleCheck" link type="success" @click="handleProcess(scope.row)"></el-button>
              </el-tooltip>
            </template>
            <template v-else>
              <el-tag effect="light" type="success">已处理</el-tag>
            </template>
          </div>
        </template>
      </el-table-column>
    </el-table>

    <el-row class="pg-container">
      <el-col :span="24">
        <pagination
          v-show="total > 0"
          v-model:limit="queryParams.size"
          v-model:page="queryParams.current"
          :total="total"
          @pagination="getList"
        />
      </el-col>
    </el-row>

    <!-- 报警详情对话框 -->
    <el-dialog
      v-model="openDetail"
      append-to-body
      class="custom-dialog detail-dialog"
      title="报警详情"
      width="1000px"
      @close="cleanupDetailMap"
      @open="initDetailMap"
    >
      <div class="detail-content">
        <div class="detail-left">
          <div class="section-title">
             <el-icon class="mr4 danger-icon"><LocationFilled /></el-icon>位置信息
          </div>
          <div class="info-row">
            <span class="info-label">经纬度：</span>
            <span class="info-value">{{ currentDetail.longitude ? currentDetail.longitude + ', ' + currentDetail.latitude : '116.3974, 39.9093' }}</span>
          </div>
          <div ref="detailMapContainer" class="detail-map-view"></div>
        </div>
        <div class="detail-right">
          <div class="info-card">
            <div class="info-item vertical">
              <span class="label">处理状态：</span>
              <div class="tag-wrapper">
                <el-tag effect="dark" size="large" :type="activeTab === 0 ? 'danger' : 'success'">
                  {{ activeTab === 0 ? '未处理' : '已处理' }}
                </el-tag>
              </div>
            </div>
            <div class="info-item vertical">
              <span class="label">报警类型：</span>
              <div class="tag-wrapper">
                <el-tag effect="plain" size="large" :type="getAlarmLevelType(currentDetail.alarmLevel)">
                   <dict-tag plain :options="alarm_type" :value="currentDetail.alarmType" />
                </el-tag>
              </div>
            </div>
            <div class="info-item">
              <span class="label">报警时间：</span>
              <span class="value">{{ currentDetail.alarmStartTime }}</span>
            </div>
            <div class="info-item">
              <span class="label">报警人：</span>
              <span class="value">{{ currentDetail.userName }}</span>
            </div>
            <div class="info-item">
              <span class="label">设备编号：</span>
              <span class="value">{{ currentDetail.hatNumber }}</span>
            </div>
          </div>
        </div>
      </div>
      <template #footer>
        <div class="dialog-footer">
          <el-button v-if="activeTab === 0 && currentDetail.alarmType === 'SOS告警'" class="blue-btn lg" disabled type="primary" @click="handleAnswer(currentDetail)">接听（S7 未交付）</el-button>
          <el-button v-if="activeTab === 0" class="outline-btn lg" @click="handleProcess(currentDetail)">去处理</el-button>
          <el-button class="outline-btn lg" @click="openDetail = false">关闭</el-button>
        </div>
      </template>
    </el-dialog>

    <!-- 接听弹窗 (设备实时画面) -->
    <el-dialog
      v-model="openAnswer"
      append-to-body
      class="video-dialog"
      :show-header="false"
      width="800px"
    >
      <div class="video-container">
        <div class="video-main">
          <div class="video-overlay">设备实时画面</div>
          <div class="video-controls">
            <div class="control-item"><el-icon><SwitchButton /></el-icon>关闭</div>
            <div class="control-item"><el-icon><Microphone /></el-icon>声音</div>
            <div class="control-item green"><el-icon><FullScreen /></el-icon>全屏</div>
            <div class="control-item"><el-icon><Refresh /></el-icon>旋转</div>
          </div>
        </div>
        <div class="video-info-footer">
          <div class="info-left">
            <div class="info-line">报警设备编号：<span>{{ currentDetail.hatNumber }}</span></div>
            <div class="info-line">人员姓名：<span>{{ currentDetail.realName }}</span></div>
            <div class="info-line">所在位置：<span>{{ currentDetail.location }}</span></div>
          </div>
          <div class="info-right">
            <el-button class="end-call-btn" type="primary" @click="openAnswer = false">结束通话</el-button>
          </div>
        </div>
      </div>
    </el-dialog>

    <!-- 处理弹窗 (填写事件说明) -->
    <el-dialog
      v-model="openProcess"
      append-to-body
      class="custom-dialog process-dialog"
      title="填写事件说明"
      width="600px"
    >
      <el-input
        v-model="processForm.description"
        maxlength="1000"
        placeholder="请填写事件说明，限制1000字"
        :rows="8"
        show-word-limit
        type="textarea"
      />
      <template #footer>
        <div class="dialog-footer">
          <el-button class="outline-btn lg" @click="openProcess = false">关闭</el-button>
          <el-button class="blue-btn lg" type="primary" @click="submitProcess">保存</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup name="SOS">
import { nextTick, watch } from 'vue';
import { useRoute } from 'vue-router';
import { listAlarmPage, handleAlarm, getAlarmDetail } from "@/api/system/sos";
import TableSkeleton from "@/components/TableSkeleton";
import { useMap } from "@/hooks/useMap";
import 'ol/ol.css';

const route = useRoute();
const { proxy } = getCurrentInstance();
const { alarm_type } = proxy.useDict("alarm_type");

// 核心状态
const activeTab = ref(0); // 0: 未处理, 1: 已处理
const loading = ref(false);
const searchLoading = ref(false);
const showSearch = ref(true);
const total = ref(0);

// 数据列表
const alarmList = ref([]);

// 对话框状态
const openDetail = ref(false);
const openAnswer = ref(false);
const openProcess = ref(false);

const currentDetail = ref({});
const processForm = reactive({
  description: ''
});

// 地图相关
const detailMapContainer = ref(null);
let detailMapUtils = null;
let detailMarker = null;

const queryParams = reactive({
  current: 1,
  size: 10,
  alarmType: '',
  userName: '',
  startTimeFrom: undefined,
  startTimeTo: undefined,
  isHandled: 0
});

/** 查询列表 */
function getList() {
  loading.value = true;
  searchLoading.value = true;
  queryParams.isHandled = activeTab.value;
  listAlarmPage(queryParams).then(response => {
    alarmList.value = response.data.records;
    total.value = response.data.total;
  }).catch(() => {
  }).finally(() => {
    loading.value = false;
    searchLoading.value = false;
  });
}

/** 搜索按钮操作 */
function handleQuery() {
  queryParams.current = 1;
  getList();
}

/** 重置按钮操作 */
function resetQuery() {
  proxy.resetForm("queryRef");
  queryParams.startTimeFrom = undefined;
  queryParams.startTimeTo = undefined;
  handleQuery();
}

/** Tab 切换操作 */
function handleTabChange(val) {
  if (activeTab.value === val) return;
  activeTab.value = val;
  handleQuery();
}

/** 详情按钮操作 */
function handleDetail(row) {
  currentDetail.value = { ...row };
  openDetail.value = true;
}

/** 接听尚未建立通话会话，S7 前不得显示已接通。 */
function handleAnswer() {
  proxy.$modal.msgWarning("接听能力未完成，真实通话在 S7 交付。本次不会建立音视频连接。");
}

/** 处理按钮操作 */
function handleProcess(row) {
  currentDetail.value = { ...row };
  processForm.description = '';
  openProcess.value = true;
}

/** 提交处理 */
function submitProcess() {
  if (!processForm.description) {
    proxy.$modal.msgError("请填写事件说明");
    return;
  }

  handleAlarm({id: currentDetail.value.id, description: processForm.description}).then(() => {
    proxy.$modal.msgSuccess("处理成功");
    openProcess.value = false;
    openDetail.value = false;
    getList();
  });
}

/** 根据告警等级获取标签类型 */
function getAlarmLevelType(level) {
  // level: 1-紧急, 2-警告, 3-一般, 4-提示
  switch (Number(level)) {
    case 1:
      return 'danger';    // 紧急 - 红色
    case 2:
      return 'warning';   // 警告 - 橙色
    case 3:
      return 'info';      // 一般 - 蓝色
    case 4:
      return 'success';   // 提示 - 绿色
    default:
      return 'info';      // 默认 - 蓝色
  }
}

/** 初始化详情地图 */
function initDetailMap() {
  // 使用 nextTick 确保 DOM 完全渲染后再初始化地图
  nextTick(() => {
    if (!detailMapContainer.value) return;

    // 初始化地图
    const utils = useMap();
    detailMapUtils = utils;
    utils.initMap(detailMapContainer.value);

    // 获取经纬度
    const lng = parseFloat(currentDetail.value.longitude || 116.3974);
    const lat = parseFloat(currentDetail.value.latitude || 39.9093);

    // 添加标记点
    if (lng && lat) {
      detailMarker = utils.addMarker([lng, lat]);
    }
  });
}

/** 清理详情地图 */
function cleanupDetailMap() {
  if (detailMapUtils) {
    if (detailMarker) {
      detailMarker.remove();
      detailMarker = null;
    }
    detailMapUtils.clearMarkers();
    detailMapUtils.cleanup();
    detailMapUtils = null;
  }
}

getList();

// 监听路由参数，处理从 WebSocket 通知跳转过来的情况
watch(
  () => route.query,
  (query) => {
    if (query.showDetail === 'true') {
      // 支持两种方式：直接传数据或通过 API 获取
      if (query.alarmData) {
        try {
          currentDetail.value = JSON.parse(query.alarmData)
          openDetail.value = true
        } catch (e) {
          console.error('解析告警数据失败:', e)
        }
      } else if (query.alarmId) {
        openAlarmDetail(String(query.alarmId))
      }
    }
  },
  { immediate: true }
)

function openAlarmDetail(alarmId) {
  loading.value = true
  getAlarmDetail(alarmId).then(res => {
    if (res.data) {
      currentDetail.value = res.data
      openDetail.value = true
    }
  }).catch(() => {
    proxy.$modal.msgError('获取告警详情失败')
  }).finally(() => {
    loading.value = false
  })
}
</script>

<style scoped lang="scss">
.app-container {
  padding: 8px 24px 24px;
}

.search-form {
  margin-bottom: 12px;
  padding: 16px 24px;
  background: var(--bg-pure);
  border-radius: 12px;
  box-shadow: var(--shadow-sm);

  :deep(.el-form-item) {
    margin-right: 24px;
    margin-bottom: 0;
    label { font-weight: 500; color: var(--text-secondary); }
  }
}

.search-btn {
  background-color: var(--color-action);
  border-color: var(--color-action);
}

.reset-btn {
  color: var(--text-secondary);
  border-color: var(--border-color);
}

.tab-container {
  margin-bottom: 8px;
  .el-button-group {
    background: var(--bg-muted);
    padding: 4px;
    border-radius: 8px;
    display: inline-flex;
  }
  .tab-btn {
    border: none !important;
    background: transparent !important;
    color: var(--text-primary) !important;
    padding: 8px 24px;
    height: 36px;
    border-radius: 6px !important;
    font-weight: 600;
    transition: none !important;
    transform: none !important;
    box-shadow: none !important;

    &.active {
      background: var(--brand-primary-hover) !important;
      color: var(--brand-primary-fg) !important;
      box-shadow: var(--shadow-md);
    }

    &:hover {
      transform: none !important;
      box-shadow: none !important;
    }
  }
}

.custom-table {
  border-radius: 12px;
  overflow: hidden;
  box-shadow: var(--shadow-sm);

  :deep(.el-table__header-wrapper) {
    th { background-color: var(--bg-table-header); color: var(--text-primary); font-weight: 600; height: 56px; }
  }

  :deep(.el-table__row) {
    height: 72px;
    td { border-bottom: 1px solid var(--border-color); }
  }
}

.operation-buttons {
  display: flex;
  justify-content: center;
  gap: 12px;
  .el-button { margin: 0; padding: 4px; font-size: 18px; }
}

.blue-btn {
  background-color: var(--brand-primary);
  border-color: var(--brand-primary);
  &.lg { padding: 10px 40px; height: auto; font-size: 16px; border-radius: 8px; }
  &:hover { background-color: var(--brand-primary-hover); border-color: var(--brand-primary-hover); }
}

.green-btn {
  background-color: var(--color-success);
  border-color: var(--color-success);
  &.lg { padding: 10px 40px; height: auto; font-size: 16px; border-radius: 8px; }
  &:hover { background-color: var(--color-success-hover, #047857); border-color: var(--color-success-hover, #047857); }
}

.outline-btn {
  border: 1px solid var(--border-color);
  color: var(--text-primary);
  &.lg { padding: 10px 40px; height: auto; font-size: 16px; border-radius: 8px; }
  &:hover { background-color: var(--bg-soft); border-color: var(--border-hover); }
}

.pg-container {
  margin-top: 24px;
  display: flex;
  justify-content: flex-end;
}

// 弹窗统一样式
.custom-dialog {
  :deep(.el-dialog) {
    border-radius: 12px;
    padding: 0;
  }
  :deep(.el-dialog__header) {
    padding: 24px 32px;
    background: var(--bg-soft);
    border-bottom: 1px solid var(--border-color);
    .el-dialog__title { font-weight: 700; font-size: 18px; color: var(--text-primary); }
  }
  :deep(.el-dialog__body) { padding: 24px 32px; background: var(--bg-soft); }
  :deep(.el-dialog__footer) { padding: 24px 32px; background: var(--bg-soft); text-align: center; }
}

// 详情弹窗特定样式
.detail-content {
  display: flex;
  gap: 24px;
  .detail-left {
    flex: 3;
    background: var(--bg-pure);
    padding: 24px;
    border-radius: 12px;
    box-shadow: var(--shadow-sm);
    display: flex;
    flex-direction: column;
    .section-title { font-size: 18px; font-weight: 700; margin-bottom: 24px; display: flex; align-items: center; }
    .info-row { margin-bottom: 16px; .info-label { color: var(--text-secondary); } .info-value { color: var(--text-primary); font-weight: 500; } }
    .detail-map-view {
      flex: 1;
      min-height: 320px;
      background: var(--bg-soft);
      border-radius: 12px;
      margin-top: 24px;
    }
  }
  .detail-right {
    flex: 2;
    background: var(--bg-pure);
    padding: 24px;
    border-radius: 12px;
    border: 1px solid var(--border-color);
    .info-item {
      margin-bottom: 24px;
      .label { color: var(--text-secondary); font-size: 16px; margin-bottom: 12px; display: block; }
      .value { color: var(--text-primary); font-size: 16px; font-weight: 500; display: block; }
      .tag-wrapper { margin-top: 12px; }

      &.vertical {
        .label { margin-bottom: 12px; }
      }
    }
  }
}

// 视频弹窗特定样式
.video-dialog {
  :deep(.el-dialog) { background: var(--bg-soft); border-radius: 0; overflow: hidden; }
  :deep(.el-dialog__body) { padding: 0; }
}

.video-container {
  .video-main {
    height: 500px;
    background: var(--bg-muted);
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    .video-overlay { font-size: 48px; color: var(--text-primary); font-weight: 700; }
    .video-controls {
      position: absolute;
      bottom: 24px;
      display: flex;
      gap: 32px;
      .control-item {
        background: var(--bg-pure);
        padding: 8px 24px;
        border-radius: 8px;
        display: flex;
        align-items: center;
        gap: 8px;
        cursor: pointer;
        font-weight: 500;
        &.green { background: var(--color-success); color: var(--color-success-foreground, #fff); }
        .el-icon { font-size: 20px; }
      }
    }
  }
  .video-info-footer {
    padding: 24px 32px;
    background: var(--bg-pure);
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
    .info-line { font-size: 16px; font-weight: 700; margin-bottom: 12px; span { font-weight: 500; color: var(--text-primary); } }
    .end-call-btn {
      padding: 12px 40px;
      font-size: 18px;
      height: auto;
      border-radius: 8px;
    }
  }
}

.process-dialog {
  :deep(.el-textarea__inner) { border-radius: 8px; font-size: 16px; }
}

.mr4 { margin-right: 4px; }
.danger-icon { color: var(--color-danger); }
.muted-icon { color: var(--text-muted); }
</style>
