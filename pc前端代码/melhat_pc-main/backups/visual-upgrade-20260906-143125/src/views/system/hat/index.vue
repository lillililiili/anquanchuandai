<template>
  <div class="app-container">
    <el-form
      v-show="showSearch"
      ref="queryRef"
      :inline="true"
      label-width="68px"
      :model="queryParams"
    >
      <el-form-item label="人员id" prop="userId">
        <el-input
          v-model="queryParams.userId"
          clearable
          placeholder="请输入人员id"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="姓名" prop="name">
        <el-input
          v-model="queryParams.name"
          clearable
          placeholder="请输入姓名"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="部门id" prop="deptId">
        <el-input
          v-model="queryParams.deptId"
          clearable
          placeholder="请输入部门id"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="部门" prop="section">
        <el-input
          v-model="queryParams.section"
          clearable
          placeholder="请输入部门"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="职位" prop="position">
        <el-input
          v-model="queryParams.position"
          clearable
          placeholder="请输入职位"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="SIM卡号" prop="simNumber">
        <el-input
          v-model="queryParams.simNumber"
          clearable
          placeholder="请输入SIM卡号"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="所在分组" prop="inGroup">
        <el-input
          v-model="queryParams.inGroup"
          clearable
          placeholder="请输入所在分组"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="手机号码" prop="phone">
        <el-input
          v-model="queryParams.phone"
          clearable
          placeholder="请输入手机号码"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="APP密码" prop="password">
        <el-input
          v-model="queryParams.password"
          clearable
          placeholder="请输入APP密码"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item label="设备编号" prop="deviceNumber">
        <el-input
          v-model="queryParams.deviceNumber"
          clearable
          placeholder="请输入设备编号"
          @keyup.enter="handleQuery"
        />
      </el-form-item>
      <el-form-item>
        <el-button icon="Search" type="primary" @click="handleQuery"
          >搜索</el-button
        >
        <el-button icon="Refresh" @click="resetQuery">重置</el-button>
      </el-form-item>
    </el-form>

    <el-row class="mb8" :gutter="10">
      <el-col :span="1.5">
        <el-button
          v-hasPermi="['system:hat:add']"
          icon="Plus"
          plain
          type="primary"
          @click="handleAdd"
          >新增</el-button
        >
      </el-col>
      <el-col :span="1.5">
        <el-button
          v-hasPermi="['system:hat:edit']"
          :disabled="single"
          icon="Edit"
          plain
          type="success"
          @click="handleUpdate"
          >修改</el-button
        >
      </el-col>
      <el-col :span="1.5">
        <el-button
          v-hasPermi="['system:hat:remove']"
          :disabled="multiple"
          icon="Delete"
          plain
          type="danger"
          @click="handleDelete"
          >删除</el-button
        >
      </el-col>
      <el-col :span="1.5">
        <el-button
          v-hasPermi="['system:hat:export']"
          icon="Download"
          plain
          type="warning"
          @click="handleExport"
          >导出</el-button
        >
      </el-col>
    </el-row>

    <el-table
      v-loading="loading"
      :data="hatList"
      @selection-change="handleSelectionChange"
    >
      <el-table-column align="center" type="selection" width="55" />
      <el-table-column align="center" label="主键id" prop="id" />
      <el-table-column align="center" label="人员id" prop="userId" />
      <el-table-column align="center" label="姓名" prop="name" />
      <el-table-column align="center" label="部门id" prop="deptId" />
      <el-table-column align="center" label="部门" prop="section" />
      <el-table-column align="center" label="职位" prop="position" />
      <el-table-column align="center" label="类型" prop="type" />
      <el-table-column align="center" label="SIM卡号" prop="simNumber" />
      <el-table-column align="center" label="所在分组" prop="inGroup" />
      <el-table-column align="center" label="手机号码" prop="phone" />
      <el-table-column align="center" label="APP密码" prop="password" />
      <el-table-column align="center" label="设备编号" prop="deviceNumber" />
      <el-table-column
        align="center"
        class-name="small-padding fixed-width"
        label="操作"
      >
        <template #default="scope">
          <el-button
            v-hasPermi="['system:hat:edit']"
            icon="Edit"
            link
            type="primary"
            @click="handleUpdate(scope.row)"
            >修改</el-button
          >
          <el-button
            v-hasPermi="['system:hat:remove']"
            icon="Delete"
            link
            type="danger"
            @click="handleDelete(scope.row)"
            >删除</el-button
          >
        </template>
      </el-table-column>
    </el-table>

    <pagination
      v-show="total > 0"
      v-model:limit="queryParams.pageSize"
      v-model:page="queryParams.pageNum"
      :total="total"
      @pagination="getList"
    />

    <!-- 添加或修改安全帽对话框 -->
    <el-dialog v-model="open" append-to-body :title="title" width="500px">
      <el-form ref="hatRef" label-width="80px" :model="form" :rules="rules">
        <el-form-item label="人员id" prop="userId">
          <el-input v-model="form.userId" placeholder="请输入人员id" />
        </el-form-item>
        <el-form-item label="姓名" prop="name">
          <el-input v-model="form.name" placeholder="请输入姓名" />
        </el-form-item>
        <el-form-item label="部门id" prop="deptId">
          <el-input v-model="form.deptId" placeholder="请输入部门id" />
        </el-form-item>
        <el-form-item label="部门" prop="section">
          <el-input v-model="form.section" placeholder="请输入部门" />
        </el-form-item>
        <el-form-item label="职位" prop="position">
          <el-input v-model="form.position" placeholder="请输入职位" />
        </el-form-item>
        <el-form-item label="SIM卡号" prop="simNumber">
          <el-input v-model="form.simNumber" placeholder="请输入SIM卡号" />
        </el-form-item>
        <el-form-item label="所在分组" prop="inGroup">
          <el-input v-model="form.inGroup" placeholder="请输入所在分组" />
        </el-form-item>
        <el-form-item label="手机号码" prop="phone">
          <el-input v-model="form.phone" placeholder="请输入手机号码" />
        </el-form-item>
        <el-form-item label="APP密码" prop="password">
          <el-input v-model="form.password" placeholder="请输入APP密码" />
        </el-form-item>
        <el-form-item label="设备编号" prop="deviceNumber">
          <el-input v-model="form.deviceNumber" placeholder="请输入设备编号" />
        </el-form-item>
        <el-form-item label="删除标志" prop="delFlag">
          <el-input v-model="form.delFlag" placeholder="请输入删除标志" />
        </el-form-item>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button type="primary" @click="submitForm">确 定</el-button>
          <el-button @click="cancel">取 消</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup name="Hat">
import { addHat, delHat, getHat, listHat, updateHat } from '@/api/system/hat';

const { proxy } = getCurrentInstance();

const hatList = ref([]);
const open = ref(false);
const loading = ref(true);
const showSearch = ref(true);
const ids = ref([]);
const single = ref(true);
const multiple = ref(true);
const total = ref(0);
const title = ref('');

const data = reactive({
  form: {},
  queryParams: {
    pageNum: 1,
    pageSize: 10,
    userId: null,
    name: null,
    deptId: null,
    section: null,
    position: null,
    type: null,
    simNumber: null,
    inGroup: null,
    phone: null,
    password: null,
    deviceNumber: null,
  },
  rules: {},
});

const { queryParams, form, rules } = toRefs(data);

/** 查询安全帽列表 */
function getList() {
  loading.value = true;
  listHat(queryParams.value).then((response) => {
    hatList.value = response.rows;
    total.value = response.total;
    loading.value = false;
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
    id: null,
    userId: null,
    name: null,
    deptId: null,
    section: null,
    position: null,
    type: null,
    simNumber: null,
    inGroup: null,
    phone: null,
    password: null,
    deviceNumber: null,
    delFlag: null,
    createTime: null,
    updateTime: null,
    createBy: null,
    updateBy: null,
  };
  proxy.resetForm('hatRef');
}

/** 搜索按钮操作 */
function handleQuery() {
  queryParams.value.pageNum = 1;
  getList();
}

/** 重置按钮操作 */
function resetQuery() {
  proxy.resetForm('queryRef');
  handleQuery();
}

// 多选框选中数据
function handleSelectionChange(selection) {
  ids.value = selection.map((item) => item.id);
  single.value = selection.length != 1;
  multiple.value = !selection.length;
}

/** 新增按钮操作 */
function handleAdd() {
  reset();
  open.value = true;
  title.value = '添加安全帽';
}

/** 修改按钮操作 */
function handleUpdate(row) {
  reset();
  const _id = row.id || ids.value;
  getHat(_id).then((response) => {
    form.value = response.data;
    open.value = true;
    title.value = '修改安全帽';
  });
}

/** 提交按钮 */
function submitForm() {
  proxy.$refs['hatRef'].validate((valid) => {
    if (valid) {
      if (form.value.id != null) {
        updateHat(form.value).then((response) => {
          proxy.$modal.msgSuccess('修改成功');
          open.value = false;
          getList();
        });
      } else {
        addHat(form.value).then((response) => {
          proxy.$modal.msgSuccess('新增成功');
          open.value = false;
          getList();
        });
      }
    }
  });
}

/** 删除按钮操作 */
function handleDelete(row) {
  const _ids = row.id || ids.value;
  proxy.$modal
    .confirm('是否确认删除安全帽编号为"' + _ids + '"的数据项？')
    .then(function () {
      return delHat(_ids);
    })
    .then(() => {
      getList();
      proxy.$modal.msgSuccess('删除成功');
    })
    .catch(() => {});
}

/** 导出按钮操作 */
function handleExport() {
  proxy.download(
    'system/hat/export',
    {
      ...queryParams.value,
    },
    `hat_${new Date().getTime()}.xlsx`
  );
}

getList();
</script>
