<template>
  <div class="app-container">
    <!-- 搜索区域 -->
    <div class="tts-header">
      <el-form ref="queryRef" class="search-form" :inline="true" :model="queryParams">
        <el-form-item label="对讲类型：">
          <el-select v-model="queryParams.broadcastType" class="w-150" clearable placeholder="全部">
            <el-option
              v-for="item in BROADCAST_TYPE_OPTIONS"
              :key="item.value"
              :label="item.label"
              :value="item.value"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="开始时间：">
          <el-date-picker
            v-model="dateRange"
            class="w-300"
            end-placeholder="结束时间"
            range-separator="至"
            start-placeholder="开始时间"
            type="daterange"
            value-format="YYYY-MM-DD"
          />
        </el-form-item>
        <el-form-item>
          <el-button :disabled="searchLoading" icon="Search" :loading="searchLoading" type="primary" @click="handleQuery">搜索</el-button>
          <el-button icon="Refresh" @click="resetQuery">清空</el-button>
        </el-form-item>
      </el-form>
    </div>

    <!-- 操作区域 -->
    <div class="operation-area">
      <el-button class="op-btn" type="primary" @click="handleAdd('single')">
        <el-icon><Microphone /></el-icon>
        <span>新建单播</span>
      </el-button>
      <el-button class="op-btn" type="primary" @click="handleAdd('team')">
        <el-icon><ChatDotRound /></el-icon>
        <span>新建群播</span>
      </el-button>
      <el-button class="op-btn" type="primary" @click="handleAdd('group')">
        <el-icon><Connection /></el-icon>
        <span>新建组播</span>
      </el-button>
    </div>

    <!-- 最近记录标题 -->
    <div class="record-title">最近广播记录</div>

    <!-- 数据表格 -->
    <TableSkeleton v-if="loading && recordList.length === 0" :columns="5" :rows="5" />
    <el-table v-else v-loading="loading && recordList.length > 0" class="custom-table" :data="recordList">
      <el-table-column align="center" label="序号" type="index" width="80" />
      <el-table-column align="center" label="对讲类型" prop="broadcastType">
        <template #default="scope">
          <span>{{ getTypeLabel(scope.row.broadcastType) }}</span>
        </template>
      </el-table-column>
      <el-table-column align="center" label="参与人员" prop="recipient" />
      <el-table-column align="center" label="发送时间" prop="sendTime" />
      <el-table-column align="center" label="内容" prop="content" :show-overflow-tooltip="true" width="300" />
      <el-table-column align="center" label="操作" width="120">
        <template #default="scope">
          <el-tooltip content="查看" placement="top">
            <el-button icon="View" link type="primary" @click="handleDetail(scope.row)"></el-button>
          </el-tooltip>
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

    <!-- 新建广播弹窗 -->
    <el-dialog v-model="dialogVisible" append-to-body class="custom-dialog" :title="dialogTitle" width="600px">
      <el-form ref="formRef" label-width="80px" :model="form">
        <el-form-item label="类型：">
          <el-select v-model="form.type" :disabled="dialogTitle === '查看'" placeholder="请选择类型" style="width: 100%" @change="handleTypeChange">
            <el-option label="单播" value="single" />
            <el-option label="群播" value="team" />
            <el-option label="组播" value="group" />
          </el-select>
        </el-form-item>
        <el-form-item label="人员：">
          <div class="person-select-wrapper">
            <div class="tag-input-container" :class="{ 'is-disabled': dialogTitle === '查看' }" @click="dialogTitle !== '查看' && openPersonSelect()">
              <el-tag
                v-for="name in form.personNames"
                :key="name"
                class="name-tag"
                :closable="dialogTitle !== '查看'"
                @close="handleRemoveTag(name)"
              >
                {{ name }}
              </el-tag>
              <span v-if="form.personNames.length === 0" class="placeholder-text">请选择人员</span>
            </div>
            <el-button v-if="dialogTitle !== '查看'" class="select-btn" @click="openPersonSelect">选择</el-button>
          </div>
        </el-form-item>
        <el-form-item label="内容：">
          <el-input
            v-model="form.content"
            placeholder="请输入您要转换为语音的文字内容..."
            :readonly="dialogTitle === '查看'"
            rows="8"
            type="textarea"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button @click="dialogVisible = false">{{ dialogTitle === '查看' ? '关闭' : '取消' }}</el-button>
          <el-button v-if="dialogTitle !== '查看'" type="primary" @click="submitForm">保存</el-button>
        </div>
      </template>
    </el-dialog>

    <!-- 人员选择弹窗 -->
    <el-dialog v-model="personSelectVisible" append-to-body class="custom-dialog" :title="personSelectTitle" width="1000px">
      <el-form class="search-form-mini" :inline="true" :model="popQueryParams">
        <template v-if="form.type !== 'group'">
          <el-form-item label="安全帽编号：">
            <el-input v-model="popQueryParams.hatNumber" class="w-150" placeholder="请输入" />
          </el-form-item>
          <el-form-item label="人员姓名：">
            <el-input v-model="popQueryParams.bindUserName" class="w-150" placeholder="请输入" />
          </el-form-item>
        </template>
        <template v-else>
          <el-form-item label="分组名称：">
            <el-input v-model="popQueryParams.groupName" class="w-200" placeholder="请输入" />
          </el-form-item>
        </template>
        <el-form-item>
          <el-button icon="Search" type="primary" @click="handlePopQuery">搜索</el-button>
          <el-button icon="Refresh" @click="resetPopQuery">清空</el-button>
        </el-form-item>
        <el-form-item v-if="form.type === 'team'" style="float: right">
          <el-button type="primary" @click="confirmPersonSelect">确定</el-button>
        </el-form-item>
      </el-form>

      <el-table
        class="custom-table"
        :data="form.type === 'group' ? groupList : personList"
        @select="handleSelect"
        @select-all="handleSelectAll"
      >
        <el-table-column align="center" label="序号" type="index" width="60" />
        <template v-if="form.type !== 'group'">
          <el-table-column align="center" label="安全帽编号" prop="hatNumber" />
          <el-table-column align="center" label="所属群组" prop="bindGroup" />
          <el-table-column align="center" label="绑定人员姓名" prop="bindUserName" />
          <el-table-column align="center" label="设备时间" prop="bindTime" width="160" />
          <el-table-column align="center" label="电量" width="120">
            <template #default="scope">
              <el-progress :color="getProgressColor(scope.row.electricityUsage)" :percentage="scope.row.electricityUsage" :show-text="false" :stroke-width="8" />
              <span class="progress-val">{{ scope.row.electricityUsage }}%</span>
            </template>
          </el-table-column>
          <el-table-column align="center" label="存储空间" width="120">
            <template #default="scope">
              <el-progress :color="getProgressColor(scope.row.storageUsage)" :percentage="scope.row.storageUsage" :show-text="false" :stroke-width="8" />
              <span class="progress-val">{{ scope.row.storageUsage }}%</span>
            </template>
          </el-table-column>
        </template>
        <template v-else>
          <el-table-column align="center" label="分组名称" prop="groupName" />
          <el-table-column align="center" label="安全帽数量" prop="safetyCount" />
        </template>
        <el-table-column align="center" label="操作" width="100">
          <template #default="scope">
            <template v-if="form.type === 'single' || form.type === 'group'">
              <el-button size="small" type="primary" @click="handleSelectRow(scope.row)">选择</el-button>
            </template>
            <template v-if="form.type === 'team'">
              <el-button
                size="small"
                :type="selectedIds.has(scope.row.hatNumber) ? 'success' : 'primary'"
                @click="handleSelectRow(scope.row)"
              >
                {{ selectedIds.has(scope.row.hatNumber) ? '已选择' : '选择' }}
              </el-button>
            </template>
          </template>
        </el-table-column>
      </el-table>

      <div class="pg-container">
        <pagination v-model:limit="popQueryParams.size" v-model:page="popQueryParams.current" :total="personTotal" @pagination="getPopList" />
      </div>
    </el-dialog>
  </div>
</template>

<script setup name="TTS">
import { Microphone, ChatDotRound, Connection } from '@element-plus/icons-vue'
import { listTtsRecord, addUnicast, addMulticast, addGroupcast } from "@/api/tts";
import { hatSafetyInfoPage } from "@/api/helmet";
import { groupList as listGroup } from "@/api/group";
import TableSkeleton from "@/components/TableSkeleton"

const { proxy } = getCurrentInstance();

// 广播类型常量
const BROADCAST_TYPE = {
  UNICAST: '01',    // 单播
  GROUPCAST: '02',  // 群播
  MULTICAST: '03'   // 组播
};

// 广播类型选项（用于下拉选择）
const BROADCAST_TYPE_OPTIONS = [
  { label: '全部', value: '' },
  { label: '单播', value: BROADCAST_TYPE.UNICAST },
  { label: '群播', value: BROADCAST_TYPE.GROUPCAST },
  { label: '组播', value: BROADCAST_TYPE.MULTICAST }
];

// 广播类型标签映射
const BROADCAST_TYPE_LABEL = {
  [BROADCAST_TYPE.UNICAST]: '单播',
  [BROADCAST_TYPE.GROUPCAST]: '群播',
  [BROADCAST_TYPE.MULTICAST]: '组播'
};

const queryParams = reactive({
  current: 1,
  size: 10,
  broadcastType: '',
  sendTimeFrom: undefined,
  sendTimeTo: undefined
});
const dateRange = ref([]);
const loading = ref(false);
const searchLoading = ref(false);
const total = ref(0);

const recordList = ref([]);

// 弹窗相关
const dialogVisible = ref(false);
const dialogTitle = ref('新建');
const form = reactive({
  type: 'single',
  personNames: [],
  target: null, // Stores deviceNo, groupName, or list of deviceNos
  content: ''
});

// 人员选择弹窗相关
const personSelectVisible = ref(false);
const personSelectTitle = ref('请选择人员');
const personTotal = ref(0);
const popQueryParams = reactive({
  current: 1,
  size: 10,
  hatNumber: '',
  bindUserName: '',
  groupName: ''
});

const personList = ref([]);
const groupList = ref([]);
const selectedIds = ref(new Set()); // 存储选中的 hatNumber，支持跨页选择

function handleQuery() {
  queryParams.current = 1;
  getList();
}

function resetQuery() {
  dateRange.value = [];
  queryParams.sendTimeFrom = undefined;
  queryParams.sendTimeTo = undefined;
  proxy.resetForm("queryRef");
  handleQuery();
}

function getList() {
  loading.value = true;
  searchLoading.value = true;
  let params = { ...queryParams };
  if (dateRange.value && dateRange.value.length === 2) {
    params.sendTimeFrom = dateRange.value[0];
    params.sendTimeTo = dateRange.value[1];
  }
  listTtsRecord(params).then(response => {
    recordList.value = response.rows || response.data.records;
    total.value = response.total || response.data.total;
  }).catch(() => {
  }).finally(() => {
    loading.value = false;
    searchLoading.value = false;
  });
}

function getTypeLabel(type) {
  return BROADCAST_TYPE_LABEL[type] || '未知';
}

function getProgressColor(percentage) {
  if (percentage < 30) return getComputedStyle(document.documentElement).getPropertyValue('--color-danger').trim() || '#dc2626';
  if (percentage < 60) return getComputedStyle(document.documentElement).getPropertyValue('--color-warning').trim() || '#f59e0b';
  return getComputedStyle(document.documentElement).getPropertyValue('--color-success').trim() || '#059669';
}

function handleAdd(type) {
  form.type = type;
  form.personNames = [];
  form.target = null;
  form.content = '';
  dialogTitle.value = '新建';
  dialogVisible.value = true;
}

function handleTypeChange() {
  form.personNames = [];
  form.target = null;
}

function openPersonSelect() {
  if (form.type === 'single') {
    personSelectTitle.value = '请选择单播人员';
  } else if (form.type === 'team') {
    personSelectTitle.value = '请选择群播人员（多选）';
    selectedIds.value.clear(); // 清空之前的选择
  } else if (form.type === 'group') {
    personSelectTitle.value = '请选择组播分组';
  }
  // 重置搜索参数
  popQueryParams.current = 1;
  popQueryParams.hatNumber = '';
  popQueryParams.bindUserName = '';
  popQueryParams.groupName = '';
  getPopList();
  personSelectVisible.value = true;
}

function getPopList() {
  if (form.type === 'group') {
    // 组播使用 hat/group/info 接口，参数为 pageNo/pageSize
    const params = {
      current: popQueryParams.current,
      size: popQueryParams.size,
      groupName: popQueryParams.groupName
    };
    listGroup(params).then(res => {
      groupList.value = res.data.records || res.rows;
      personTotal.value = res.data.total || res.total;
    });
  } else {
    // 单播和群播使用 hat/safety/info/page 接口
    const params = {
      current: popQueryParams.current,
      size: popQueryParams.size,
      hatNumber: popQueryParams.hatNumber,
      bindUserName: popQueryParams.bindUserName
    };
    hatSafetyInfoPage(params).then(res => {
      personList.value = (res.data.records || res.rows).map(item => ({
        ...item,
        selected: false
      }));
      personTotal.value = res.data.total || res.total;
      // 数据加载后回显选中状态
      setTimeout(() => {
        toggleRowSelection();
      }, 0);
    });
  }
}

function handlePopQuery() {
  popQueryParams.current = 1;
  getPopList();
}

function resetPopQuery() {
  popQueryParams.hatNumber = '';
  popQueryParams.bindUserName = '';
  popQueryParams.groupName = '';
  popQueryParams.current = 1;
  getPopList();
}

function handleSelectRow(row) {
  if (form.type === 'single') {
    form.personNames = [row.bindUserName];
    form.target = row.hatNumber;
    personSelectVisible.value = false;
  } else if (form.type === 'group') {
    form.personNames = [row.groupName];
    form.target = row.id;
    personSelectVisible.value = false;
  } else if (form.type === 'team') {
    // 群播多选逻辑
    const hatNumber = row.hatNumber;
    const userName = row.bindUserName;
    if (selectedIds.value.has(hatNumber)) {
      selectedIds.value.delete(hatNumber);
      const idx = form.personNames.indexOf(userName);
      if (idx > -1) form.personNames.splice(idx, 1);
    } else {
      selectedIds.value.add(hatNumber);
      if (!form.personNames.includes(userName)) form.personNames.push(userName);
    }
    // 更新target
    form.target = Array.from(selectedIds.value);
  }
}

function toggleSelect(row) {
  const isSelected = selectedIds.value.has(row.hatNumber);
  if (isSelected) {
    selectedIds.value.delete(row.hatNumber);
  } else {
    selectedIds.value.add(row.hatNumber);
  }
  // 更新当前行的显示状态
  row.selected = !isSelected;
}

// 回显选中状态
function toggleRowSelection() {
  const table = proxy.$el.querySelector('.custom-table');
  if (!table) return;
  const tableInstance = table.__vue__;
  if (!tableInstance) return;

  personList.value.forEach(row => {
    if (selectedIds.value.has(row.hatNumber)) {
      tableInstance.toggleRowSelection(row, true);
    }
  });
}

// 单选处理
function handleSelect(selection, row) {
  const isSelected = selection.includes(row);
  if (isSelected) {
    selectedIds.value.add(row.hatNumber);
  } else {
    selectedIds.value.delete(row.hatNumber);
  }
}

// 全选处理
function handleSelectAll(selection) {
  if (selection.length === personList.value.length) {
    // 全选
    personList.value.forEach(row => {
      selectedIds.value.add(row.hatNumber);
    });
  } else {
    // 取消全选
    personList.value.forEach(row => {
      selectedIds.value.delete(row.hatNumber);
    });
  }
}

function confirmPersonSelect() {
  if (form.type === 'team') {
    const selected = personList.value.filter(p => selectedIds.value.has(p.hatNumber));
    form.personNames = selected.map(p => p.bindUserName);
    form.target = selected.map(p => p.hatNumber);
  }
  personSelectVisible.value = false;
}

function handleRemoveTag(name) {
  const index = form.personNames.indexOf(name);
  if (index > -1) {
    form.personNames.splice(index, 1);
    if (Array.isArray(form.target)) {
      form.target.splice(index, 1);
    } else {
      form.target = null;
    }
  }
}

function submitForm() {
  if (!form.target || (Array.isArray(form.target) && form.target.length === 0)) {
    proxy.$modal.msgError('请选择人员或分组');
    return;
  }
  if (!form.content) {
    proxy.$modal.msgError('请输入广播内容');
    return;
  }

  const data = {
    content: form.content
  };

  let promise;
  if (form.type === 'single') {
    data.hatNumber = form.target;
    data.participant = form.personNames[0];
    promise = addUnicast(data);
  } else if (form.type === 'group') {
    data.groupId = form.target;
    promise = addMulticast(data);
  } else if (form.type === 'team') {
    data.hatNumber = form.target.join(',');
    data.participant = form.target.join(',');
    promise = addGroupcast(data);
  }

  promise.then(() => {
    proxy.$modal.msgSuccess('发布成功');
    dialogVisible.value = false;
    handleQuery();
  });
}

function handleDetail(row) {
  form.type = row.broadcastType === BROADCAST_TYPE.UNICAST ? 'single' : (row.broadcastType === BROADCAST_TYPE.MULTICAST ? 'group' : 'team');
  form.personNames = row.members ? row.members.split('、') : [];
  form.content = row.content;
  dialogTitle.value = '查看';
  dialogVisible.value = true;
}

getList();
</script>

<style scoped lang="scss">
@import "@/assets/styles/variables.module.scss";

.app-container {
  padding: 8px var(--section-padding) var(--section-padding);
  background-color: var(--bg-base); 
  min-height: calc(100vh - 60px);
}

.tts-header {
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
    td { border-bottom: 1px solid var(--border-color) !important; }
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

.dialog-footer {
  display: flex;
  justify-content: center;
  gap: var(--space-5);
  padding-bottom: var(--space-3);

  .el-button {
    width: 120px;
    height: 40px;
    border-radius: 8px;
    font-weight: var(--font-semibold);
  }
}

.person-select-wrapper {
  display: flex;
  width: 100%;
  gap: var(--gap-tight);
  align-items: flex-start;

  .tag-input-container {
    flex: 1;
    min-height: 36px;
    padding: var(--space-1) var(--space-3);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    background-color: var(--bg-pure);
    cursor: pointer;
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-1);
    align-items: center;
    transition: all 0.3s;

    &:hover {
      border-color: var(--border-hover);
    }

    &.is-disabled {
      background-color: var(--bg-soft);
      cursor: not-allowed;
      border-color: var(--border-color);
    }

    .placeholder-text {
      color: var(--text-placeholder);
      font-size: var(--text-sm);
    }

    .name-tag {
      border-radius: 4px;
      background-color: var(--bg-soft);
      border: 1px solid var(--border-color);
      color: var(--text-primary);
    }
  }

  .select-btn {
    height: 41px !important;
    padding: 0 16px;
    margin: 0;
    border: 1px solid $border;
    border-radius: 8px;
    background: transparent;
    color: $text-primary;
    font-weight: var(--font-medium);
    box-sizing: border-box;
    display: flex;
    align-items: center;
    justify-content: center;

    &:hover {
      border-color: $brand-primary;
      color: $brand-primary;
      background: rgba(37, 99, 235, 0.05);
    }
  }
}
</style>
