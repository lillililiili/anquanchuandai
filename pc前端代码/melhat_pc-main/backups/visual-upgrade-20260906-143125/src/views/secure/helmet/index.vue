<template>
  <div class="app-container">
    <el-form
      v-show="showSearch"
      ref="queryRef"
      :inline="true"
      label-width="68px"
      :model="queryParams"
    >
      <el-form-item label="设备编号" prop="deviceFlashid">
        <el-input
          v-model="queryParams.deviceFlashid"
          class="w-240"
          clearable
          placeholder="请输入设备编号"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item>
        <el-button
          v-hasPermi="['system:hat:list']"
          :disabled="searchLoading"
          icon="Search"
          :loading="searchLoading"
          type="primary"
          @click="handleQuery"
          >搜索</el-button
        >
        <el-button
          v-hasPermi="['system:hat:list']"
          icon="Refresh"
          @click="resetQuery"
          >重置</el-button
        >
        <el-button
          v-hasPermi="['system:hat:sync']"
          icon="Refresh"
          plain
          type="primary"
          @click="handleSync"
          >一键同步</el-button
        >
      </el-form-item>
    </el-form>

    <TableSkeleton v-if="loading && hatListData.length === 0" :columns="4" :rows="5" />
    <el-table
      v-else
      v-loading="loading && hatListData.length > 0"
      :data="hatListData"
    >
      <el-table-column align="center" label="设备名称" prop="deviceName" />
      <el-table-column align="center" label="设备编号" prop="deviceFlashid" />
      <el-table-column align="center" label="描述" prop="hatDescription" />
      <el-table-column
        align="center"
        class-name="small-padding fixed-width"
        label="操作"
      >
        <template #default="scope">
          <el-tooltip content="绑定" placement="top">
            <el-button
              v-hasPermi="['system:hat:bind']"
              icon="Link"
              link
              type="primary"
              @click="handleBind(scope.row)"
            ></el-button>
          </el-tooltip>
          <el-tooltip content="通话" placement="top">
            <el-button
              v-hasPermi="['system:hat:call']"
              icon="Phone"
              link
              type="primary"
              @click="handleCall(scope.row)"
            ></el-button>
          </el-tooltip>
          <el-tooltip content="详情" placement="top">
            <el-button
              icon="View"
              link
              type="primary"
              @click="handleDetail(scope.row)"
            ></el-button>
          </el-tooltip>
        </template>
      </el-table-column>
    </el-table>

    <el-row class="pg-container">
      <el-col :lg="12" :sm="24">
        <pagination
          v-show="total > 0"
          v-model:limit="queryParams.pageSize"
          v-model:page="queryParams.pageNum"
          :total="total"
          @pagination="getList"
        />
      </el-col>
    </el-row>

    <!-- 详情 -->
    <el-drawer v-model="viewOpen" append-to-body size="800px" :title="title">
      <el-descriptions border :column="1">
        <el-descriptions-item label="设备名称">
          {{ form.deviceName || "-" }}
        </el-descriptions-item>
        <el-descriptions-item label="设备编号">
          {{ form.deviceFlashid || "-" }}
        </el-descriptions-item>
        <el-descriptions-item label="设备描述">
          {{ form.hatDescription || "-" }}
        </el-descriptions-item>
        <el-descriptions-item label="绑定人员">
          {{
            form.deptName
              ? `${form.deptName} - ${form.name || ""}`
              : form.name || "-"
          }}
        </el-descriptions-item>
      </el-descriptions>

      <el-collapse v-model="activeNames" class="mt-4">
        <el-collapse-item name="1" title="绑定记录">
          <el-table v-loading="loading" :data="form.bindRecordList">
            <el-table-column align="center" label="绑定人" prop="peopleName" />
            <el-table-column align="center" label="事件" width="80px">
              <template #default="scope">
                <el-tag v-if="scope.row.peopleId" type="success">绑定</el-tag>
                <el-tag v-else type="danger">解除绑定</el-tag>
              </template>
            </el-table-column>
            <el-table-column
              align="center"
              label="操作时间"
              prop="createTime"
            />
            <el-table-column align="center" label="操作人" prop="createBy" />
          </el-table>
        </el-collapse-item>
      </el-collapse>

      <template #footer>
        <div class="dialog-footer">
          <el-button @click="cancel">关 闭</el-button>
        </div>
      </template>
    </el-drawer>

    <!-- 绑定抽屉 -->
    <el-drawer v-model="bindOpen" append-to-body size="500px" title="绑定头盔">
      <el-form
        ref="bindRef"
        label-width="80px"
        :model="bindForm"
        :rules="bindRules"
      >
        <el-form-item label="部门" prop="deptId">
          <el-tree-select
            v-model="bindForm.deptId"
            check-strictly
            class="w-full"
            :data="deptOptions"
            placeholder="请选择部门"
            :props="{ value: 'id', label: 'label', children: 'children' }"
            value-key="id"
            @change="bindDeptFind($event)"
          />
        </el-form-item>
        <el-form-item label="人员" prop="userId">
          <el-select
            v-model="bindForm.userId"
            class="w-full"
            clearable
            placeholder="请选择人员"
          >
            <el-option
              v-for="item in bindStaffOptions"
              :key="item.userId"
              :label="item.nickName"
              :value="item.userId"
            />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button type="primary" @click="submitBind">确 定</el-button>
          <el-button @click="cancelBind">取 消</el-button>
        </div>
      </template>
    </el-drawer>

    <!-- 通话iframe弹窗 -->
    <el-dialog
      v-model="callOpen"
      append-to-body
      destroy-on-close
      title="通话"
      width="800px"
    >
      <iframe
        v-if="callUrl"
        allow="camera; microphone"
        frameborder="0"
        sandbox="allow-scripts allow-same-origin allow-forms"
        :src="callUrl"
        style="width: 100%; height: 600px; border: none"
      ></iframe>
    </el-dialog>
  </div>
</template>

<script setup name="Helmat">
import { hatList, hatBind, hatSync, hatDetail } from "@/api/helmet";
import { deptTreeSelect } from "@/api/system/user";
import { getDepartment } from "@/api/task/schedule";
import { listUser } from "@/api/system/user";
import { findDeptName } from "@/utils/common";
import TableSkeleton from "@/components/TableSkeleton";

const { proxy } = getCurrentInstance();

const hatListData = ref([]);
const viewOpen = ref(false);
const loading = ref(true);
const searchLoading = ref(false);
const showSearch = ref(true);
const total = ref(0);
const title = ref("");
const deptName = ref("");
const deptOptions = ref(undefined);
const staffOptions = ref(undefined);

const data = reactive({
  form: {},
  queryParams: {
    pageNum: 1,
    pageSize: 10,
    deviceFlashid: undefined,
  },
  rules: {},
});

const activeNames = ref("1");
const { queryParams, form } = toRefs(data);

/** 查询头盔列表 */
function getList() {
  loading.value = true;
  searchLoading.value = true;
  hatList(queryParams.value).then((response) => {
    hatListData.value = response.rows;
    total.value = response.total;
  }).finally(() => {
    loading.value = false;
    searchLoading.value = false;
  });
}

// 取消按钮
function cancel() {
  viewOpen.value = false;
}

/** 搜索按钮操作 */
function handleQuery() {
  queryParams.value.pageNum = 1;
  getList();
}

/** 根据名称筛选部门树 */
watch(deptName, (val) => {
  proxy.$refs["deptTreeRef"].filter(val);
});

/** 查询部门下拉树结构 */
function getDeptTree() {
  deptTreeSelect().then((response) => {
    deptOptions.value = response.data;
  });
}

/** 查询部门下员工 */
function deptFind(val) {
  staffOptions.value = undefined;
  getDepartment(val).then((response) => {
    staffOptions.value = response.data;
  });
}

/** 重置按钮操作 */
function resetQuery() {
  proxy.resetForm("queryRef");
  queryParams.value.deptId = undefined;
  handleQuery();
}

/** 详情 */
function handleDetail(row) {
  hatDetail(row.id).then((response) => {
    form.value = response.data;
    viewOpen.value = true;
    title.value = "头盔详情";
  });
}

// 绑定相关
const bindOpen = ref(false);
const bindStaffOptions = ref([]);
const currentHat = ref(null);

const bindForm = reactive({
  deptId: undefined,
  userId: undefined,
});

const bindRules = {
  deptId: { required: true, message: "请选择部门" },
  userId: { required: true, message: "请选择人员" },
};

// 打开绑定抽屉
function handleBind(row) {
  currentHat.value = row;
  bindOpen.value = true;
}

// 取消绑定
function cancelBind() {
  bindOpen.value = false;
  bindForm.deptId = undefined;
  bindForm.userId = undefined;
  bindStaffOptions.value = [];
}

// 查询部门下员工
function bindDeptFind(val) {
  bindStaffOptions.value = [];
  bindForm.userId = undefined;
  listUser({
    pageNum: queryParams.value.pageNum,
    pageSize: queryParams.value.pageSize,
    deptId: val,
  }).then((response) => {
    bindStaffOptions.value = response.rows;
  });
}

// 提交绑定
function submitBind() {
  proxy.$refs["bindRef"].validate((valid) => {
    if (valid) {
      const selectedUser = bindStaffOptions.value.find(
        (user) => user.userId === bindForm.userId
      );

      hatBind({
        id: currentHat.value.id,
        deptId: bindForm.deptId,
        userId: bindForm.userId,
        deptName: findDeptName(deptOptions.value, bindForm.deptId),
        name: selectedUser?.nickName || "",
      }).then(() => {
        proxy.$modal.msgSuccess("绑定成功");
        bindOpen.value = false;
        getList();
      });
    }
  });
}

// 一键同步
function handleSync() {
  proxy.$modal.confirm("是否确认同步所有头盔设备？").then(() => {
    hatSync().then(() => {
      proxy.$modal.msgSuccess("同步成功");
      getList();
    });
  });
}

// 通话相关
const callOpen = ref(false);
const callUrl = ref("");

// 通话
function handleCall(row) {
  callUrl.value = row.deviceIframeUrl;
  callOpen.value = true;
}

getDeptTree();
getList();
</script>
