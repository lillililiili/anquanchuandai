<template>
  <div class="app-container">
    <ModuleHeader module="group" />
    <el-form
      v-show="showSearch"
      ref="queryRef"
      class="search-form"
      :inline="true"
      :model="queryParams"
    >
      <el-form-item label="分组名称" prop="groupName">
        <el-input
          v-model="queryParams.groupName"
          class="w-240"
          clearable
          placeholder="请输入分组名称"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item>
        <el-button :disabled="searchLoading" icon="Search" :loading="searchLoading" type="primary" @click="handleQuery"
          >搜索</el-button
        >
        <el-button icon="Refresh" @click="resetQuery">重置</el-button>
      </el-form-item>
    </el-form>

    <el-row class="mb8 action-bar" :gutter="10">
      <el-col :span="1.5">
        <el-button icon="Plus" plain type="primary" @click="handleAdd"
          >新增分组</el-button
        >
      </el-col>
    </el-row>

    <TableSkeleton v-if="loading && groupList.length === 0" :columns="4" :rows="5" />
    <el-table v-else v-loading="loading && groupList.length > 0" class="custom-table" :data="groupList">
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
      <el-table-column align="center" label="分组名称" prop="groupName" />
      <el-table-column
        align="center"
        label="分组描述"
        prop="groupDesc"
        show-overflow-tooltip
      />
      <el-table-column
        align="center"
        label="安全帽数量"
        prop="safetyCount"
        width="120"
      />
      <el-table-column
        align="center"
        class-name="small-padding fixed-width"
        label="操作"
        width="200"
      >
        <template #default="scope">
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
        </template>
      </el-table-column>
    </el-table>

    <pagination
      v-show="total > 0"
      v-model:limit="queryParams.size"
      v-model:page="queryParams.current"
      class="custom-pagination"
      :total="total"
      @pagination="getList"
    />

    <!-- 添加或修改分组对话框 -->
    <el-dialog
      v-model="open"
      append-to-body
      class="custom-dialog"
      :title="title"
      width="500px"
    >
      <el-form ref="groupRef" label-width="120px" :model="form" :rules="rules">
        <el-form-item label="分组名称：" prop="groupName">
          <el-input
            v-model="form.groupName"
            maxlength="30"
            placeholder="限制 30 个字"
          />
        </el-form-item>
        <el-form-item label="分组描述：" prop="groupDesc">
          <el-input
            v-model="form.groupDesc"
            placeholder="请输入内容"
            :rows="4"
            type="textarea"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button class="cancel-btn" @click="cancel">取 消</el-button>
          <el-button class="save-btn" type="primary" @click="submitForm"
            >保 存</el-button
          >
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup name="Group">
import {
  groupList as getGroupList,
  groupInfo,
  groupInfoUpdate,
  groupInfoDelete,
} from "@/api/group";
import TableSkeleton from "@/components/TableSkeleton";

const { proxy } = getCurrentInstance();

const groupList = ref([]);
const open = ref(false);
const loading = ref(false);
const searchLoading = ref(false);
const showSearch = ref(true);
const total = ref(0);
const title = ref("");

const data = reactive({
  form: {},
  queryParams: {
    current: 1,
    size: 10,
    groupName: undefined,
  },
  rules: {
    groupName: [
      { required: true, message: "分组名称不能为空", trigger: "blur" },
    ],
  },
});

const { queryParams, form, rules } = toRefs(data);

/** 查询分组列表 */
function getList() {
  loading.value = true;
  searchLoading.value = true;
  getGroupList({
    current: queryParams.value.current,
    size: queryParams.value.size,
    groupName: queryParams.value.groupName,
  })
    .then((response) => {
      const { records, total: totalCount } = response.data;
      groupList.value = records || [];
      total.value = totalCount || 0;
    })
    .catch(() => {
    })
    .finally(() => {
      loading.value = false;
      searchLoading.value = false;
    });
}

// 取消按钮
function cancel() {
  open.value = false;
  reset();
}

// 表单重置
function reset() {
  form.value = {
    id: undefined,
    groupName: undefined,
    groupDesc: undefined,
    safetyCount: 0,
  };
  proxy.resetForm("groupRef");
}

/** 搜索按钮操作 */
function handleQuery() {
  queryParams.value.current = 1;
  getList();
}

/** 重置按钮操作 */
function resetQuery() {
  proxy.resetForm("queryRef");
  handleQuery();
}

/** 新增按钮操作 */
function handleAdd() {
  reset();
  open.value = true;
  title.value = "新增分组";
}

/** 修改按钮操作 */
function handleUpdate(row) {
  reset();
  form.value = { ...row };
  open.value = true;
  title.value = "编辑分组";
}

/** 提交按钮 */
function submitForm() {
  proxy.$refs["groupRef"].validate((valid) => {
    if (valid) {
      if (form.value.id) {
        // 编辑
        groupInfoUpdate(form.value).then((response) => {
          proxy.$modal.msgSuccess("修改成功");
          open.value = false;
          getList();
        });
      } else {
        // 新增
        groupInfo(form.value).then((response) => {
          proxy.$modal.msgSuccess("新增成功");
          open.value = false;
          getList();
        });
      }
    }
  });
}

/** 删除按钮操作 */
function handleDelete(row) {
  proxy.$modal
    .confirm('是否确认删除名称为"' + row.groupName + '"的数据项？')
    .then(function () {
      groupInfoDelete(row.id).then(() => {
        proxy.$modal.msgSuccess("删除成功");
        getList();
      });
    })
    .catch(() => {});
}

getList();
</script>

<style scoped lang="scss">
@import "@/assets/styles/variables.module.scss";

.app-container {
  padding: 8px 24px 24px;
  background-color: $bg-base;
  min-height: 100vh;
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
    label {
      font-weight: var(--font-medium);
      color: var(--text-secondary);
    }
  }
}

.action-bar {
  margin-bottom: 16px;
}

.custom-table {
  border-radius: $radius;
  overflow: hidden;
  box-shadow: $shadow-sm;
  border: 1px solid $border;

  :deep(.el-table__header-wrapper) {
    th {
      background-color: $bg-table-header;
      color: var(--text-primary);
      font-weight: var(--font-semibold);
      height: 50px;
    }
  }

  :deep(.el-table__row) {
    td {
      height: 60px;
      color: $text-secondary;
    }
  }
}

.custom-pagination {
  margin-top: 24px;
  justify-content: flex-end;
}

.custom-dialog {
  :deep(.el-dialog) {
    border-radius: $radius-xl;
    overflow: hidden;
  }
  :deep(.el-dialog__header) {
    margin: 0;
    padding: 20px 24px;
    border-bottom: 1px solid $border;
    .el-dialog__title {
      font-weight: var(--font-semibold);
      color: var(--text-primary);
    }
  }
  :deep(.el-dialog__body) {
    padding: 32px 32px;
    background-color: $bg-base;
  }
  :deep(.el-dialog__footer) {
    padding: 16px 24px;
    border-top: 1px solid $border;
    background-color: $bg-base;
  }
}

.save-btn {
  background-color: $brand-primary;
  border-color: $brand-primary;
  padding: 10px 32px;
  font-weight: var(--font-medium);
  border-radius: $radius-sm;
  &:hover {
    background-color: $brand-primary-hover;
    border-color: $brand-primary-hover;
  }
}

.cancel-btn {
  padding: 10px 32px;
  border-radius: $radius-sm;
  border-color: $border;
  color: $text-secondary;
  &:hover {
    background-color: $bg-soft;
    color: $text-primary;
  }
}
</style>
