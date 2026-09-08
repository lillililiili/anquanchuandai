<template>
  <div class="app-container">
    <ModuleHeader module="system" :title="$route.meta.title || '系统管理'" />
    <el-table
      v-loading="loading"
      :data="moduleList"
      @selection-change="handleSelectionChange"
    >
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
      <el-table-column
        v-if="columns[0].visible"
        key="moduleName"
        align="center"
        label="用户编号"
        prop="moduleName"
      />

      <el-table-column
        v-if="columns[1].visible"
        key="revealOrNo"
        align="center"
        label="是否展示"
        prop="revealOrNo"
      >
        <template #default="scope">
          <el-switch
            v-model="scope.row.revealOrNo"
            active-value="0"
            inactive-value="1"
            @change="handleModuleStatusChange(scope.row)"
          ></el-switch>
        </template>
      </el-table-column>
      <el-table-column label="展示位置" prop="displayPosition" width="100">
        <template #default="scope">
          <el-select
            v-model="scope.row.displayPosition"
            placeholder="请选择展示位置"
            @change="updateModule(scope.row)"
          >
            <el-option
              v-for="option in fd_module_status"
              :key="option.value"
              :label="option.label"
              :value="option.value"
            />
          </el-select>
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

    <!-- 添加或修改大屏模块配置对话框 -->
    <el-dialog v-model="open" append-to-body :title="title" width="500px">
      <el-form ref="moduleRef" label-width="80px" :model="form" :rules="rules">
        <el-form-item label="模块名称" prop="moduleName">
          <el-input v-model="form.moduleName" placeholder="请输入模块名称" />
        </el-form-item>
        <el-col :span="12">
          <el-form-item label="是否展示">
            <el-radio-group v-model="form.revealOrNo">
              <el-radio-button
                v-for="dict in fd_module_or_no"
                :key="dict.value"
                :label="dict.value"
              >
                {{ dict.label }}
              </el-radio-button>
            </el-radio-group>
          </el-form-item>
        </el-col>
        <el-col :span="12">
          <el-form-item label="展示位置">
            <el-select
              v-model="form.displayPosition"
              placeholder="请选择展示位置"
            >
              <el-option
                v-for="dict in fd_module_status"
                :key="dict.value"
                :label="dict.label"
                :value="dict.value"
              ></el-option>
            </el-select>
          </el-form-item>
        </el-col>
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

<script setup name="Module">
import {
  addModule,
  delModule,
  getModule,
  listModule,
  updateModule
} from '@/api/system/module'

const { proxy } = getCurrentInstance()

const moduleList = ref([])
const open = ref(false)
const loading = ref(true)
const showSearch = ref(true)
const ids = ref([])
const single = ref(true)
const multiple = ref(true)
const total = ref(0)
const title = ref('')

const { fd_module_status, fd_module_or_no } = proxy.useDict(
  'fd_module_status',
  'fd_module_or_no'
)

const data = reactive({
  form: {},
  queryParams: {
    pageNum: 1,
    pageSize: 10,
    moduleName: null,
    revealOrNo: null,
    displayPosition: null
  },
  rules: {}
})

const { queryParams, form, rules } = toRefs(data)
// 列显隐信息
const columns = ref([
  { key: 0, label: `模块名称`, visible: true },
  { key: 1, label: `是否展示`, visible: true }
])

/** 是否展示状态修改  */
function handleModuleStatusChange(row) {
  let text = row.revealOrNo === '0' ? '展示' : '不展示'
  proxy.$modal
    .confirm('确认要"' + text + '""' + row.moduleName + '"吗?')
    .then(function () {
      return updateModule(row)
    })
    .then(() => {
      proxy.$modal.msgSuccess(text + '成功')
    })
    .catch(function () {
      row.revealOrNo = row.revealOrNo === '0' ? '1' : '0'
    })
}

/** 查询大屏模块配置列表 */
function getList() {
  loading.value = true
  listModule(queryParams.value).then(response => {
    moduleList.value = response.rows
    total.value = response.total
    loading.value = false
  })
}

// 取消按钮
function cancel() {
  open.value = false
  reset()
}

// 表单重置
function reset() {
  form.value = {
    id: null,
    moduleName: null,
    revealOrNo: null,
    displayPosition: null
  }
  proxy.resetForm('moduleRef')
}

/** 搜索按钮操作 */
function handleQuery() {
  queryParams.value.pageNum = 1
  getList()
}

/** 重置按钮操作 */
function resetQuery() {
  proxy.resetForm('queryRef')
  handleQuery()
}

// 多选框选中数据
function handleSelectionChange(selection) {
  ids.value = selection.map(item => item.id)
  single.value = selection.length != 1
  multiple.value = !selection.length
}

/** 新增按钮操作 */
function handleAdd() {
  reset()
  open.value = true
  title.value = '添加大屏模块配置'
}

/** 修改按钮操作 */
function handleUpdate(row) {
  reset()
  const _id = row.id || ids.value
  getModule(_id).then(response => {
    form.value = response.data
    open.value = true
    title.value = '修改大屏模块配置'
  })
}

/** 提交按钮 */
function submitForm() {
  proxy.$refs['moduleRef'].validate(valid => {
    if (valid) {
      if (form.value.id != null) {
        updateModule(form.value).then(response => {
          proxy.$modal.msgSuccess('修改成功')
          open.value = false
          getList()
        })
      } else {
        addModule(form.value).then(response => {
          proxy.$modal.msgSuccess('新增成功')
          open.value = false
          getList()
        })
      }
    }
  })
}

/** 删除按钮操作 */
function handleDelete(row) {
  const _ids = row.id || ids.value
  proxy.$modal
    .confirm('是否确认删除大屏模块配置编号为"' + _ids + '"的数据项？')
    .then(function () {
      return delModule(_ids)
    })
    .then(() => {
      getList()
      proxy.$modal.msgSuccess('删除成功')
    })
    .catch(() => {})
}

/** 导出按钮操作 */
function handleExport() {
  proxy.download(
    'system/module/export',
    {
      ...queryParams.value
    },
    `module_${new Date().getTime()}.xlsx`
  )
}

getList()
</script>

<style lang="scss" scoped>
.pagination-container {
  margin-bottom: 18px;
  margin-top: 15px;
  padding: 0 !important;
  background-color: transparent;
  position: relative;

  .el-pagination {
    right: 20px !important;
  }
}
</style>
