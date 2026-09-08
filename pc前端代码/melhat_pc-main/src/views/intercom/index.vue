<template>
  <div class="app-container">
    <ModuleHeader module="intercom" />
    <!-- 搜索区 -->
    <div class="intercom-header">
      <el-form ref="queryRef" class="search-form" :inline="true" :model="queryParams">
        <el-form-item label="对讲类型：">
          <el-select v-model="queryParams.intercomType" class="w-150" clearable placeholder="全部">
            <el-option label="全部" value="" />
            <el-option v-for="item in intercomTypeOptions" :key="item.value" :label="item.label" :value="item.value" />
          </el-select>
        </el-form-item>
        <el-form-item label="开始时间：">
          <el-date-picker v-model="dateRange" class="w-300" end-placeholder="结束时间" range-separator="至"
            start-placeholder="开始时间" type="daterange" value-format="YYYY-MM-DD" />
        </el-form-item>
        <el-form-item>
          <el-button :disabled="searchLoading" icon="Search" :loading="searchLoading" type="primary"
            @click="handleQuery">搜索</el-button>
          <el-button icon="Refresh" @click="resetQuery">清空</el-button>
        </el-form-item>
      </el-form>
    </div>

    <!-- 操作按钮 -->
    <div class="operation-area">
      <el-button class="op-btn" type="primary" @click="handleSingleCall">
        <el-icon>
          <Microphone />
        </el-icon>
        <span>新建单呼</span>
      </el-button>
      <el-button class="op-btn" type="primary" @click="handleGroupCall">
        <el-icon>
          <ChatDotRound />
        </el-icon>
        <span>新建群呼</span>
      </el-button>
      <el-button class="op-btn" type="primary" @click="handleTeamCall">
        <el-icon>
          <Connection />
        </el-icon>
        <span>新建组呼</span>
      </el-button>
    </div>

    <div class="record-title">最近对讲记录</div>

    <!-- 表格 -->
    <TableSkeleton v-if="loading && recordList.length === 0" :columns="6" :rows="5" />
    <el-table v-else v-loading="loading && recordList.length > 0" class="custom-table" :data="recordList">
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
      <el-table-column align="center" label="序号" type="index" width="80" />
      <el-table-column align="center" label="对讲类型" prop="intercomType">
        <template #default="scope">
          <span>{{ getTypeLabel(scope.row.intercomType) }}</span>
        </template>
      </el-table-column>
      <el-table-column align="center" label="参与人员" prop="participant" />
      <el-table-column align="center" label="开始时间" prop="startTime" />
      <el-table-column align="center" label="结束时间" prop="endTime">
        <template #default="scope">
          <span>{{ scope.row.endTime || '-' }}</span>
        </template>
      </el-table-column>
      <el-table-column align="center" label="时长" prop="duration">
        <template #default="scope">
          <span>{{ formatDuration(scope.row.duration) }}</span>
        </template>
      </el-table-column>
      <!-- <el-table-column align="center" label="操作" width="180">
        <template #default="scope">
          <el-button v-if="!scope.row.endTime" size="small" type="danger"
            @click="handleEndCall(scope.row)">结束对讲</el-button>
          <el-button size="small" type="primary" @click="handlePlayback(scope.row)">回放</el-button>
        </template>
      </el-table-column> -->
    </el-table>
    <div class="pg-container">
      <pagination v-show="total > 0" v-model:limit="queryParams.size" v-model:page="queryParams.current" :total="total"
        @pagination="getList" />
    </div>

    <!--组呼弹窗组件 -->
    <el-dialog v-model="dialogVisible" append-to-body :before-close="handleDialogClose" class="custom-dialog"
      :close-on-click-modal="true" :close-on-press-escape="true" :title="dialogTitle" width="1000px">
      <el-form class="search-form-mini" :inline="true" :model="popQueryParams">
        <el-form-item v-if="activeType !== 'team'" label="安全帽编号：">
          <el-input v-model="popQueryParams.deviceNo" class="w-150" placeholder="请输入" />
        </el-form-item>
        <el-form-item v-if="activeType !== 'team'" label="人员姓名：">
          <el-input v-model="popQueryParams.userName" class="w-150" placeholder="请输入" />
        </el-form-item>
        <el-form-item v-if="activeType === 'team'" label="分组名称：">
          <el-input v-model="popQueryParams.groupName" class="w-200" placeholder="请输入" />
        </el-form-item>
        <el-form-item>
          <el-button icon="Search" type="primary" @click="handlePopSearch">搜索</el-button>
          <el-button icon="Refresh" @click="handlePopReset">清空</el-button>
        </el-form-item>
        <el-form-item v-if="activeType === 'group'" style="float: right">
          <el-button type="primary" @click="confirmGroupCall">确定</el-button>
        </el-form-item>
      </el-form>

      <el-table class="custom-table" :data="activeType === 'team' ? groupListData : personList" :row-key="getRowKey"
        @select="handleSelect" @select-all="handleSelectAll">
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
        <el-table-column align="center" label="序号" type="index" width="60" />
        <template v-if="activeType !== 'team'">
          <el-table-column align="center" label="安全帽编号" prop="deviceNo" />
          <el-table-column align="center" label="所属群组" prop="group" />
          <el-table-column align="center" label="绑定人员姓名" prop="userName" />
          <el-table-column align="center" label="设备时间" prop="deviceTime" width="160" />
          <el-table-column align="center" label="电量" width="120">
            <template #default="scope">
              <el-progress :color="getProgressColor(scope.row.battery)" :percentage="scope.row.battery"
                :show-text="false" :stroke-width="8" />
              <span class="progress-val">{{ scope.row.battery }}%</span>
            </template>
          </el-table-column>
          <el-table-column align="center" label="存储空间" width="120">
            <template #default="scope">
              <el-progress :color="getProgressColor(scope.row.storage)" :percentage="scope.row.storage"
                :show-text="false" :stroke-width="8" />
              <span class="progress-val">{{ scope.row.storage }}%</span>
            </template>
          </el-table-column>
        </template>
        <template v-if="activeType === 'team'">
          <el-table-column align="center" label="分组名称" prop="groupName" />
          <el-table-column align="center" label="安全帽数量" prop="safetyCount" />
        </template>
        <el-table-column align="center" label="操作" width="120">
          <template #default="scope">
            <el-button v-if="activeType === 'single' || activeType === 'team'" size="small" type="primary"
              @click="handleCall(scope.row)">呼叫</el-button>
            <el-button v-if="activeType === 'group'" size="small"
              :type="selectedIds.has(scope.row.deviceNo) ? 'success' : 'primary'"
              @click="handleGroupSelect(scope.row)">{{ selectedIds.has(scope.row.deviceNo) ? '已选择' : '选择' }}</el-button>
          </template>
        </el-table-column>
      </el-table>

      <div class="dialog-pg-container">
        <pagination v-model:limit="popPageSize" v-model:page="popPageNum" :total="popTotal"
          @pagination="handlePopPagination" />
      </div>
    </el-dialog>

    <!-- 视频对讲弹窗 - 使用独立组件 -->
    <AgoraVideoDialog v-model="openVideo" :title="videoTitle" :credentials="agoraCredentials"
      :device-no="videoDeviceNo" :user-name="videoUserName"
      :is-playback="videoTitle === '回放'" @hangup="handleHangup" @replay="handleReplay" @credentials-clear="agoraCredentials = null" />
  </div>
</template>

<script setup name="Intercom">
import { Microphone, ChatDotRound, Connection, Refresh } from '@element-plus/icons-vue'
import { ElMessageBox } from 'element-plus'
import { listIntercomRecord, createSingleCall, createGroupCall, createTeamCall, endIntercom, getIntercomRecord } from '@/api/intercom'
import { groupList } from '@/api/group'
import { hatSafetyInfoPage } from '@/api/helmet'
import { formatDuration } from '@/utils/index'
import TableSkeleton from "@/components/TableSkeleton"
import AgoraVideoDialog from '@/components/AgoraVideoDialog/index.vue'
import { getCurrentInstance, ref, reactive } from 'vue'

const { proxy } = getCurrentInstance();

// 声网凭证（传递给 AgoraVideoDialog）
const agoraCredentials = ref(null);

// 对讲类型选项
const intercomTypeOptions = [
  { label: '单呼', value: '01' },
  { label: '组呼', value: '02' },
  { label: '群呼', value: '03' }
];

const queryParams = reactive({
  current: 1,
  size: 10,
  intercomType: ''
});
const dateRange = ref([]);
const loading = ref(false);
const searchLoading = ref(false);
const total = ref(0);
const recordList = ref([]);

// 弹窗相关
const dialogVisible = ref(false);
const dialogTitle = ref('');
const activeType = ref(''); // single, team, group
const popQueryParams = reactive({
  deviceNo: '',
  userName: '',
  groupName: ''
});
const popTotal = ref(0);
const popPageNum = ref(1);
const popPageSize = ref(10);

// 视频弹窗相关
const openVideo = ref(false);
const videoTitle = ref('详情');
const currentRecordId = ref(null);
const videoDeviceNo = ref('');
const videoUserName = ref('');

const personList = ref([]);
const groupListData = ref([]);
const selectedIds = ref(new Set()); // 存储选中的 deviceNo
const selectedRows = ref(new Map()); // 存储选中人员的完整数据，key=deviceNo

// ============ 业务功能 ============

// 查询
function handleQuery() {
  queryParams.current = 1;
  getList();
}

// 重置查询条件
function resetQuery() {
  dateRange.value = [];
  queryParams.intercomType = '';
  proxy.resetForm("queryRef");
  handleQuery();
}

// 查询列表
function getList() {
  loading.value = true;
  searchLoading.value = true;
  const params = {
    current: queryParams.current,
    size: queryParams.size,
    intercomType: queryParams.intercomType || undefined
  };
  if (dateRange.value && dateRange.value.length === 2) {
    params.startTimeFrom = dateRange.value[0];
    params.startTimeTo = dateRange.value[1];
  }
  listIntercomRecord(params).then(res => {
    if (res.code === 200) {
      recordList.value = res.data.records || [];
      total.value = res.data.total || 0;
    }
  }).catch(() => {
  }).finally(() => {
    loading.value = false;
    searchLoading.value = false;
  });
}

// 获取类型标签
function getTypeLabel(type) {
  const item = intercomTypeOptions.find(opt => opt.value === type);
  return item ? item.label : '未知';
}

// 获取进度条颜色
function getProgressColor(percentage) {
  if (percentage < 30) return getComputedStyle(document.documentElement).getPropertyValue('--color-danger').trim() || '#dc2626';
  if (percentage < 60) return getComputedStyle(document.documentElement).getPropertyValue('--color-warning').trim() || '#f59e0b';
  return getComputedStyle(document.documentElement).getPropertyValue('--color-success').trim() || '#059669';
}

// 获取弹窗人员列表
function getPersonList() {
  const params = {
    current: popPageNum.value,
    size: popPageSize.value,
    hatNumber: popQueryParams.deviceNo || undefined,
    userName: popQueryParams.userName || undefined
  };
  hatSafetyInfoPage(params).then(res => {
    if (res.code === 200) {
      personList.value = (res.data.records || []).map(item => ({
        ...item,
        selected: false,
        deviceNo: item.hatNumber || item.deviceNo,
        userName: item.userName || item.bindUserName,
        group: item.bindGroup || item.groupName || item.group,
        deviceTime: item.bindTime || item.deviceTime || item.updateTime,
        battery: item.battery || 85,
        storage: item.storage || 85
      }));
      popTotal.value = res.data.total || 0;
      // 数据加载后回显选中状态
      setTimeout(() => {
        toggleRowSelection();
      }, 0);
    }
  });
}

// 获取弹窗分组列表
function getGroupListData() {
  const params = {
    current: popPageNum.value,
    size: popPageSize.value,
    groupName: popQueryParams.groupName || undefined
  };
  groupList(params).then(res => {
    if (res.code === 200) {
      const data = res.data?.records || res.data || [];
      groupListData.value = data.map(item => ({
        ...item,
        safetyCount: item.safetyCount || item.count || 0
      }));
      popTotal.value = res.data?.total || data.length;
    }
  });
}

// 弹窗搜索
function handlePopSearch() {
  popPageNum.value = 1;
  if (activeType.value === 'team') {
    getGroupListData();
  } else {
    getPersonList();
  }
}

// 弹窗重置
function handlePopReset() {
  popPageNum.value = 1;
  popQueryParams.deviceNo = '';
  popQueryParams.userName = '';
  popQueryParams.groupName = '';
  if (activeType.value === 'team') {
    getGroupListData();
  } else {
    getPersonList();
  }
}

// 弹窗分页
function handlePopPagination() {
  if (activeType.value === 'team') {
    getGroupListData();
  } else {
    getPersonList();
  }
}

// 单呼弹窗
function handleSingleCall() {
  dialogTitle.value = '请选择单呼人员';
  activeType.value = 'single';
  dialogVisible.value = true;
  popPageNum.value = 1;
  popQueryParams.deviceNo = '';
  popQueryParams.userName = '';
  getPersonList();
}

// 群呼弹窗
function handleGroupCall() {
  dialogTitle.value = '请选择群呼人员';
  activeType.value = 'group';
  dialogVisible.value = true;
  popPageNum.value = 1;
  popQueryParams.deviceNo = '';
  popQueryParams.userName = '';
  getPersonList();
}

// 组呼弹窗
function handleTeamCall() {
  dialogTitle.value = '请选择组呼分组';
  activeType.value = 'team';
  dialogVisible.value = true;
  popPageNum.value = 1;
  popQueryParams.groupName = '';
  getGroupListData();
}

// 组呼的呼叫
function handleCall(row) {
  const apiCall = activeType.value === 'single'
    ? createSingleCall({ hatNumber: row.deviceNo, participant: row.userName })
    : activeType.value === 'team'
      ? createTeamCall({ groupId: row.id, hatNumber: row.hatNumber || row.deviceNos, participant: row.participant || row.userNames })
      : createGroupCall({ hatNumber: row.deviceNo, participant: row.userName });

  apiCall.then(res => {
    if (res.code === 200) {
      currentRecordId.value = res.data?.id;
      videoTitle.value = '呼叫详情';
      dialogVisible.value = false;
      getList();

      // 提取声网凭证
      const credentials = extractAgoraCredentials(res.data);
      if (credentials?.agoraAppId) {
        // 保存设备信息用于显示
        videoDeviceNo.value = row.deviceNo || '';
        videoUserName.value = row.userName || '';
        agoraCredentials.value = credentials;
        openVideo.value = true;
      } else {
        proxy.$modal.msgWarning('未获取到音视频凭证，仅创建了对讲记录');
      }
    }
  });
}

/**
 * 从API响应中提取声网凭证
 */
function extractAgoraCredentials(res) {
  const { agoraAppId, channelName, agoraUid, agoraToken } = res;
  return {
    agoraAppId,
    channelName,
    agoraUid,
    agoraToken
  };
}

/**
 * 挂断处理
 */
function handleHangup() {
  // 如果不是回放，结束对讲
  if (videoTitle.value !== '回放' && agoraCredentials.value?.channelName) {
    endIntercom({ channel: agoraCredentials.value.channelName }).then(() => {
      getList();
    });
  }
  agoraCredentials.value = null;
}

/**
 * 重播处理
 */
function handleReplay() {
  if (currentRecordId.value) {
    getIntercomRecord(currentRecordId.value).then(res => {
      if (res.code === 200) {
        const credentials = extractAgoraCredentials(res.data);
        if (credentials?.agoraAppId) {
          agoraCredentials.value = credentials;
        }
      }
    });
  }
}

// 获取行唯一标识
function getRowKey(row) {
  return row.deviceNo || row.id;
}

// 回显选中状态
function toggleRowSelection() {
  const table = proxy.$el.querySelector('.custom-table');
  if (!table) return;
  const tableInstance = table.__vue__;
  if (!tableInstance) return;

  personList.value.forEach(row => {
    if (selectedIds.value.has(row.deviceNo)) {
      tableInstance.toggleRowSelection(row, true);
    }
  });
}

// 单选处理
function handleSelect(selection, row) {
  const isSelected = selection.includes(row);
  if (isSelected) {
    selectedIds.value.add(row.deviceNo);
    selectedRows.value.set(row.deviceNo, { ...row });
  } else {
    selectedIds.value.delete(row.deviceNo);
    selectedRows.value.delete(row.deviceNo);
  }
}

// 全选处理
function handleSelectAll(selection) {
  if (selection.length === personList.value.length) {
    // 全选
    personList.value.forEach(row => {
      selectedIds.value.add(row.deviceNo);
      selectedRows.value.set(row.deviceNo, { ...row });
    });
  } else {
    // 取消全选
    personList.value.forEach(row => {
      selectedIds.value.delete(row.deviceNo);
      selectedRows.value.delete(row.deviceNo);
    });
  }
}

// 群呼选择/取消选择（行内按钮点击）
function handleGroupSelect(row) {
  const deviceNo = row.deviceNo;
  if (selectedIds.value.has(deviceNo)) {
    selectedIds.value.delete(deviceNo);
    selectedRows.value.delete(deviceNo);
  } else {
    selectedIds.value.add(deviceNo);
    selectedRows.value.set(deviceNo, { ...row });
  }
  // 更新表格选中状态显示
  const table = proxy.$el.querySelector('.custom-table');
  if (table && table.__vue__) {
    table.__vue__.toggleRowSelection(row, selectedIds.value.has(deviceNo));
  }
}

// 确认群呼
function confirmGroupCall() {
  if (selectedIds.value.size === 0) {
    proxy.$modal.msgWarning('请选择至少一个人员进行群呼');
    return;
  }
  const hatNumbers = [];
  const participants = [];
  selectedRows.value.forEach((row) => {
    hatNumbers.push(row.deviceNo);
    participants.push(row.userName);
  });
  createGroupCall({
    hatNumber: hatNumbers.join(','),
    participant: participants.join(',')
  }).then(res => {
    if (res.code === 200) {
      currentRecordId.value = res.data?.id;
      videoTitle.value = '呼叫详情';
      dialogVisible.value = false;
      selectedIds.value.clear();
      selectedRows.value.clear();
      getList();

      const credentials = extractAgoraCredentials(res.data);
      if (credentials?.agoraAppId) {
        agoraCredentials.value = credentials;
        openVideo.value = true;
      } else {
        proxy.$modal.msgWarning('未获取到音视频凭证，仅创建了对讲记录');
      }
    }
  });
}

// 结束对讲
function handleEndCall(row) {
  ElMessageBox.confirm('确定要结束该对讲吗？', '提示', {
    confirmButtonText: '确定',
    cancelButtonText: '取消',
    type: 'warning'
  }).then(() => {
    endIntercom({ channel: row.channel }).then(res => {
      if (res.code === 200) {
        proxy.$modal.msgSuccess('已结束对讲');
        // 如果当前正在播放该对讲，关闭弹窗
        if (currentRecordId.value === row.id && openVideo.value) {
          openVideo.value = false;
          agoraCredentials.value = null;
        }
        getList();
      }
    });
  }).catch(() => { });
}

// 回放
function handlePlayback(row) {
  videoTitle.value = '回放';
  currentRecordId.value = row.id;

  getIntercomRecord(row.id).then(res => {
    if (res.code === 200) {
      const credentials = extractAgoraCredentials(res.data);
      if (credentials?.agoraAppId) {
        // 保存设备信息用于显示
        videoDeviceNo.value = res.data?.hatNumber || '';
        videoUserName.value = res.data?.participant || '';
        agoraCredentials.value = credentials;
        openVideo.value = true;
      } else {
        proxy.$modal.msgWarning('未获取到音视频凭证');
      }
    }
  });
}

// 弹窗关闭处理
function handleDialogClose() {
  dialogVisible.value = false;
  selectedIds.value.clear();
  selectedRows.value.clear();
}

// 页面加载时获取列表
getList();
</script>

<style scoped lang="scss">
@import "@/assets/styles/variables.module.scss";

.app-container {
  padding: 8px var(--section-padding) var(--section-padding);
  background-color: var(--bg-base);
  min-height: calc(100vh - 60px);
}

.intercom-header {
  .search-form {
    margin-bottom: var(--space-3);
    padding: var(--space-4) var(--section-padding);
    background: var(--bg-pure);
    border-radius: 12px;
    box-shadow: var(--shadow-sm);

    :deep(.el-form-item) {
      margin-right: var(--section-padding);
      margin-bottom: 0;

      label {
        font-weight: var(--font-medium);
        color: var(--text-secondary);
      }
    }
  }
}

.record-title {
  font-size: var(--text-2xl);
  font-weight: var(--font-bold);
  color: var(--text-primary);
  margin-bottom: var(--space-5);
}

.custom-table {
  border-radius: 12px;
  overflow: hidden;
  box-shadow: var(--shadow-sm);

  :deep(.el-table__header-wrapper) {
    th {
      color: var(--text-primary);
      font-weight: var(--font-semibold);
      height: 56px;
    }
  }

  :deep(.el-table__row) {
    height: 72px;

    td {
      border-bottom: 1px solid var(--border-color) !important;
    }
  }
}

.operation-area {
  display: flex;
  margin-bottom: var(--space-5);

  .op-btn {
    width: 140px;
    height: 42px;
    font-size: var(--text-sm);
    font-weight: var(--font-bold);
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--gap-tight);
    transition: all 0.3s;
    background-color: var(--color-primary);
    border-color: var(--color-primary);

    &:hover {
      transform: translateY(-2px);
      box-shadow: var(--shadow-glow);
    }

    .el-icon {
      font-size: var(--text-lg);
    }
  }
}

.pg-container {
  margin-top: var(--space-5);
  display: flex;
  justify-content: flex-end;
}

.search-form-mini {
  margin-bottom: var(--space-5);
}

.dialog-pg-container {
  margin-top: var(--space-5);
  display: flex;
  justify-content: flex-end;
  padding-right: var(--section-padding);
}

.progress-val {
  font-size: var(--text-xs);
  color: var(--text-secondary);
  margin-left: var(--space-2);
}

.custom-dialog {
  :deep(.el-dialog__header) {
    padding: var(--space-5) var(--section-padding);
    border-bottom: 1px solid var(--border-color);

    .el-dialog__title {
      font-weight: var(--font-bold);
    }
  }

  :deep(.el-dialog__body) {
    padding: var(--section-padding);
  }
}
</style>
