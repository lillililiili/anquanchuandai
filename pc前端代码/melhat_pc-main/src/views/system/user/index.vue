<template>
  <div class="app-container">
    <ModuleHeader module="system" :title="$route.meta.title || '系统管理'" />
    <el-row :gutter="20">
      <!--部门数据-->
      <el-col :span="4" :xs="24">
        <div class="head-container">
          <el-input
            v-model="deptName"
            clearable
            placeholder="请输入部门名称"
            prefix-icon="Search"
            style="margin-bottom: 20px"
          />
        </div>
        <div class="head-container">
          <el-tree
            ref="deptTreeRef"
            :data="deptOptions"
            default-expand-all
            :expand-on-click-node="false"
            :filter-node-method="filterNode"
            highlight-current
            node-key="id"
            :props="{ label: 'label', children: 'children' }"
            @node-click="handleNodeClick"
          />
        </div>
      </el-col>
      <!--用户数据-->
      <el-col :span="20" :xs="24">
        <div ref="searchRef">
          <el-form class="search-form"
            v-show="showSearch"
            ref="queryRef"
            :inline="true"
            label-width="68px"
            :model="queryParams"
          >
            <el-form-item label="登录名" prop="userName">
              <el-input
                v-model="queryParams.userName"
                clearable
                placeholder="请输入登录名"
                class="w-240"
                @keyup.enter="handleQuery"
              />
            </el-form-item>
            <el-form-item label="手机号码" prop="phonenumber">
              <el-input
                v-model="queryParams.phonenumber"
                clearable
                placeholder="请输入手机号码"
                class="w-240"
                @keyup.enter="handleQuery"
              />
            </el-form-item>
            <el-form-item label="状态" prop="status">
              <el-select
                v-model="queryParams.status"
                clearable
                placeholder="用户状态"
                class="w-240"
              >
                <el-option
                  v-for="dict in sys_normal_disable"
                  :key="dict.value"
                  :label="dict.label"
                  :value="dict.value"
                />
              </el-select>
            </el-form-item>
            <el-form-item label="创建时间" style="width: auto">
              <el-date-picker
                v-model="dateRange"
                end-placeholder="结束日期"
                range-separator="-"
                start-placeholder="开始日期"
                type="daterange"
                value-format="YYYY-MM-DD"
              ></el-date-picker>
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
                v-hasPermi="['system:user:add']"
                icon="Plus"
                plain
                type="primary"
                @click="handleAdd"
                >新增</el-button
              >
            </el-col>
            <el-col :span="1.5">
              <el-button
                v-hasPermi="['system:user:edit']"
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
                v-hasPermi="['system:user:remove']"
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
                v-hasPermi="['system:user:import']"
                icon="Upload"
                plain
                type="info"
                @click="handleImport"
                >导入</el-button
              >
            </el-col>
            <el-col :span="1.5">
              <el-button
                v-hasPermi="['system:user:export']"
                icon="Download"
                plain
                type="warning"
                @click="handleExport"
                >导出</el-button
              >
            </el-col>
          </el-row>
        </div>

        <el-table
          v-loading="loading"
          :data="userList"
          :height="contentHeight + 'px'"
          @selection-change="handleSelectionChange"
        >
      <template #empty><BrandedEmpty compact description="暂无记录" /></template>
          <el-table-column align="center" type="selection" width="50" />
          <el-table-column
            v-if="columns[0].visible"
            key="userId"
            align="center"
            label="用户编号"
            prop="userId"
          />
          <el-table-column
            v-if="columns[1].visible"
            key="userName"
            align="center"
            label="登录名"
            prop="userName"
            :show-overflow-tooltip="true"
          />
          <el-table-column
            v-if="columns[2].visible"
            key="nickName"
            align="center"
            label="用户昵称"
            prop="nickName"
            :show-overflow-tooltip="true"
          />
          <el-table-column
            v-if="columns[3].visible"
            key="deptName"
            align="center"
            label="部门"
            prop="dept.deptName"
            :show-overflow-tooltip="true"
          />
          <el-table-column
            v-if="columns[4].visible"
            key="phonenumber"
            align="center"
            label="手机号码"
            prop="phonenumber"
            width="120"
          />
          <el-table-column
            v-if="columns[5].visible"
            key="status"
            align="center"
            label="状态"
          >
            <template #default="scope">
              <el-switch
                v-model="scope.row.status"
                active-value="0"
                inactive-value="1"
                @change="handleStatusChange(scope.row)"
              ></el-switch>
            </template>
          </el-table-column>
          <el-table-column
            v-if="columns[6].visible"
            align="center"
            label="创建时间"
            prop="createTime"
            width="190"
          >
            <template #default="scope">
              <span>{{ parseTime(scope.row.createTime) }}</span>
            </template>
          </el-table-column>
          <el-table-column
            align="center"
            class-name="small-padding fixed-width"
            label="操作"
            width="190"
          >
            <template #default="scope">
              <el-tooltip
                v-if="scope.row.userId !== 1"
                content="修改"
                placement="top"
              >
                <el-button
                  v-hasPermi="['system:user:edit']"
                  icon="Edit"
                  link
                  type="primary"
                  @click="handleUpdate(scope.row)"
                ></el-button>
              </el-tooltip>
              <el-tooltip
                v-if="scope.row.userId !== 1"
                content="删除"
                placement="top"
              >
                <el-button
                  v-hasPermi="['system:user:remove']"
                  icon="Delete"
                  link
                  type="danger"
                  @click="handleDelete(scope.row)"
                ></el-button>
              </el-tooltip>
              <el-tooltip
                v-if="scope.row.userId !== 1"
                content="重置密码"
                placement="top"
              >
                <el-button
                  v-hasPermi="['system:user:resetPwd']"
                  icon="Key"
                  link
                  type="primary"
                  @click="handleResetPwd(scope.row)"
                ></el-button>
              </el-tooltip>
              <el-tooltip
                v-if="scope.row.userId !== 1"
                content="分配角色"
                placement="top"
              >
                <el-button
                  v-hasPermi="['system:user:edit']"
                  icon="CircleCheck"
                  link
                  type="primary"
                  @click="handleAuthRole(scope.row)"
                ></el-button>
              </el-tooltip>
            </template>
          </el-table-column>
        </el-table>
      </el-col>
    </el-row>

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

    <!-- 添加或修改用户配置对话框 -->
    <el-dialog v-model="open" append-to-body :title="title" width="600px">
      <el-form ref="userRef" label-width="80px" :model="form" :rules="rules">
        <el-row>
          <el-col :span="12">
            <el-form-item label="用户昵称" prop="nickName">
              <el-input
                v-model="form.nickName"
                maxlength="30"
                placeholder="请输入用户昵称"
              />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="归属部门" prop="deptId">
              <el-tree-select
                v-model="form.deptId"
                check-strictly
                :data="deptOptions"
                placeholder="请选择归属部门"
                :props="{ value: 'id', label: 'label', children: 'children' }"
                value-key="id"
              />
            </el-form-item>
          </el-col>
        </el-row>
        <el-row>
          <el-col :span="12">
            <el-form-item label="手机号码" prop="phonenumber">
              <el-input
                v-model="form.phonenumber"
                maxlength="11"
                placeholder="请输入手机号码"
              />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="邮箱" prop="email">
              <el-input
                v-model="form.email"
                maxlength="50"
                placeholder="请输入邮箱"
              />
            </el-form-item>
          </el-col>
        </el-row>
        <el-row>
          <el-col :span="12">
            <el-form-item
              v-if="form.userId == undefined"
              label="登录名"
              prop="userName"
            >
              <el-input
                v-model="form.userName"
                maxlength="30"
                placeholder="请输入登录名"
              />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item
              v-if="form.userId == undefined"
              label="用户密码"
              prop="password"
            >
              <el-input
                v-model="form.password"
                maxlength="20"
                placeholder="请输入用户密码"
                show-password
                type="password"
              />
            </el-form-item>
          </el-col>
        </el-row>
        <el-row>
          <el-col :span="12">
            <el-form-item label="用户性别">
              <el-select v-model="form.sex" placeholder="请选择">
                <el-option
                  v-for="dict in sys_user_sex"
                  :key="dict.value"
                  :label="dict.label"
                  :value="dict.value"
                ></el-option>
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="状态">
              <el-radio-group v-model="form.status">
                <el-radio
                  v-for="dict in sys_normal_disable"
                  :key="dict.value"
                  :label="dict.value"
                  >{{ dict.label }}</el-radio
                >
              </el-radio-group>
            </el-form-item>
          </el-col>
        </el-row>
        <el-row>
          <el-col :span="12">
            <el-form-item label="岗位">
              <el-select v-model="form.postIds" multiple placeholder="请选择">
                <el-option
                  v-for="item in postOptions"
                  :key="item.postId"
                  :disabled="item.status == 1"
                  :label="item.postName"
                  :value="item.postId"
                ></el-option>
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="角色">
              <el-select v-model="form.roleIds" multiple placeholder="请选择">
                <el-option
                  v-for="item in roleOptions"
                  :key="item.roleId"
                  :disabled="item.status == 1"
                  :label="item.roleName"
                  :value="item.roleId"
                ></el-option>
              </el-select>
            </el-form-item>
          </el-col>
        </el-row>
        <el-row>
          <el-col :span="24">
            <el-form-item label="协助分组">
              <el-select
                v-model="form.assistGroup"
                multiple
                placeholder="请选择"
                style="width: 100%"
              >
                <el-option
                  v-for="item in hat_assist_group"
                  :key="item.value"
                  :label="item.label"
                  :value="item.value"
                ></el-option>
              </el-select>
            </el-form-item>
          </el-col>
        </el-row>
        <el-row>
          <el-col :span="24">
            <el-form-item label="备注">
              <el-input
                v-model="form.remark"
                placeholder="请输入内容"
                type="textarea"
              ></el-input>
            </el-form-item>
          </el-col>
        </el-row>
        <el-row>
          <el-col class="dialog-footer" :span="24">
            <ul class="password-rule">
              <li class="password-rule-title">密码规则:</li>
              <li class="password-rule-item">1.密码最少长度为8位;</li>
              <li class="password-rule-item">
                2.密码应至少包含数字、大小写字母及特殊字符中的三种;
              </li>
              <li class="password-rule-item">
                3.禁山使用一个相同的数字或字符作为密码，如bbb、b34bb、2b3b4b等
              </li>
              <li class="password-rule-item">
                4.禁止使用三个连续升序或降序的数字或字母作为密码，如123456、abc、def等;
              </li>
              <li class="password-rule-item">5.禁止使用用户账户号作为密码。</li>
            </ul>
          </el-col>
        </el-row>
      </el-form>
      <template #footer>
        <div class="dialog-footer">
          <el-button type="primary" @click="submitForm">确 定</el-button>
          <el-button @click="cancel">取 消</el-button>
        </div>
      </template>
    </el-dialog>

    <!-- 用户导入对话框 -->
    <el-dialog
      v-model="upload.open"
      append-to-body
      :title="upload.title"
      width="400px"
    >
      <el-upload
        ref="uploadRef"
        accept=".xlsx, .xls"
        :action="upload.url + '?updateSupport=' + upload.updateSupport"
        :auto-upload="false"
        :disabled="upload.isUploading"
        drag
        :headers="upload.headers"
        :limit="1"
        :on-progress="handleFileUploadProgress"
        :on-success="handleFileSuccess"
      >
        <el-icon class="el-icon--upload"><upload-filled /></el-icon>
        <div class="el-upload__text">将文件拖到此处，或<em>点击上传</em></div>
        <template #tip>
          <div class="el-upload__tip text-center">
            <div class="el-upload__tip">
              <el-checkbox
                v-model="upload.updateSupport"
              />是否更新已经存在的用户数据
            </div>
            <span>仅允许导入xls、xlsx格式文件。</span>
            <el-link
              style="font-size: 12px; vertical-align: baseline"
              type="primary"
              :underline="false"
              @click="importTemplate"
              >下载模板</el-link
            >
          </div>
        </template>
      </el-upload>
      <template #footer>
        <div class="dialog-footer">
          <el-button type="primary" @click="submitFileForm">确 定</el-button>
          <el-button @click="upload.open = false">取 消</el-button>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script setup name="User">
import {
  addUser,
  changeUserStatus,
  delUser,
  deptTreeSelect,
  getUser,
  listUser,
  resetUserPwd,
  updateUser,
} from "@/api/system/user";
import { getToken } from "@/utils/auth";
import { ElMessageBox } from "element-plus";

const router = useRouter();
const { proxy } = getCurrentInstance();
const { sys_normal_disable, sys_user_sex, hat_assist_group } = proxy.useDict(
  "sys_normal_disable",
  "sys_user_sex",
  "hat_assist_group"
);

const userList = ref([]);
const open = ref(false);
const loading = ref(true);
const showSearch = ref(true);
const ids = ref([]);
const single = ref(true);
const multiple = ref(true);
const total = ref(0);
const title = ref("");
const dateRange = ref([]);
const deptName = ref("");
const deptOptions = ref(undefined);
const initPassword = ref(undefined);
const postOptions = ref([]);
const roleOptions = ref([]);
const contentHeight = ref("");
const searchRef = ref(null);
/*** 用户导入参数 */
const upload = reactive({
  // 是否显示弹出层（用户导入）
  open: false,
  // 弹出层标题（用户导入）
  title: "",
  // 是否禁用上传
  isUploading: false,
  // 是否更新已经存在的用户数据
  updateSupport: 0,
  // 设置上传的请求头部
  headers: { Authorization: "Bearer " + getToken() },
  // 上传的地址
  url: import.meta.env.VITE_APP_BASE_API + "/system/user/importData",
});
// 列显隐信息
const columns = ref([
  { key: 0, label: `用户编号`, visible: true },
  { key: 1, label: `登录名`, visible: true },
  { key: 2, label: `用户昵称`, visible: true },
  { key: 3, label: `部门`, visible: true },
  { key: 4, label: `手机号码`, visible: true },
  { key: 5, label: `状态`, visible: true },
  { key: 6, label: `创建时间`, visible: true },
]);

/** 密码校验函数 */
function validatePassword(rule, value, callback) {
  if (!value) {
    callback(new Error("用户密码不能为空"));
    return;
  }
  // 1. 密码最少长度为8位
  if (value.length < 8) {
    callback(new Error("密码长度不能少于8位"));
    return;
  }
  if (value.length > 20) {
    callback(new Error("密码长度不能超过20位"));
    return;
  }
  // 2. 密码应至少包含数字、大小写字母及特殊字符中的三种
  let typeCount = 0;
  if (/\d/.test(value)) typeCount++; // 数字
  if (/[a-z]/.test(value)) typeCount++; // 小写字母
  if (/[A-Z]/.test(value)) typeCount++; // 大写字母
  if (/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(value)) typeCount++; // 特殊字符
  if (typeCount < 3) {
    callback(new Error("密码应至少包含数字、大小写字母及特殊字符中的三种"));
    return;
  }
  // 3. 禁止使用一个相同的数字或字符作为密码（如bbb、b34bb、2b3b4b等）
  // 检查是否超过一半是相同字符
  const charCounts = {};
  for (const char of value) {
    charCounts[char] = (charCounts[char] || 0) + 1;
    if (charCounts[char] > value.length / 2) {
      callback(new Error("禁止使用过多相同的数字或字符作为密码"));
      return;
    }
  }
  // 4. 禁止使用三个连续升序或降序的数字或字母作为密码
  for (let i = 0; i < value.length - 2; i++) {
    const c1 = value.charCodeAt(i);
    const c2 = value.charCodeAt(i + 1);
    const c3 = value.charCodeAt(i + 2);
    // 检查数字连续 (如123、321)
    if (c1 >= 48 && c1 <= 57 && c2 >= 48 && c2 <= 57 && c3 >= 48 && c3 <= 57) {
      if ((c2 === c1 + 1 && c3 === c2 + 1) || (c2 === c1 - 1 && c3 === c2 - 1)) {
        callback(new Error("禁止使用连续升序或降序的数字作为密码"));
        return;
      }
    }
    // 检查字母连续 (如abc、cba)
    if (c1 >= 65 && c1 <= 90 && c2 >= 65 && c2 <= 90 && c3 >= 65 && c3 <= 90) {
      if ((c2 === c1 + 1 && c3 === c2 + 1) || (c2 === c1 - 1 && c3 === c2 - 1)) {
        callback(new Error("禁止使用连续升序或降序的字母作为密码"));
        return;
      }
    }
    if (c1 >= 97 && c1 <= 122 && c2 >= 97 && c2 <= 122 && c3 >= 97 && c3 <= 122) {
      if ((c2 === c1 + 1 && c3 === c2 + 1) || (c2 === c1 - 1 && c3 === c2 - 1)) {
        callback(new Error("禁止使用连续升序或降序的字母作为密码"));
        return;
      }
    }
  }
  // 5. 禁止使用用户账户号作为密码
  if (form.value.userName && value.toLowerCase() === form.value.userName.toLowerCase()) {
    callback(new Error("禁止使用用户账户号作为密码"));
    return;
  }
  callback();
}

const data = reactive({
  form: {},
  queryParams: {
    pageNum: 1,
    pageSize: 10,
    userName: undefined,
    phonenumber: undefined,
    status: undefined,
    deptId: undefined,
  },
  rules: {
    userName: [
      { required: true, message: "登录名不能为空", trigger: "blur" },
      {
        min: 2,
        max: 20,
        message: "登录名长度必须介于 2 和 20 之间",
        trigger: "blur",
      },
    ],
    nickName: [
      { required: true, message: "用户昵称不能为空", trigger: "blur" },
    ],
    password: [
      { required: true, validator: validatePassword, trigger: "blur" },
    ],
    email: [
      {
        type: "email",
        message: "请输入正确的邮箱地址",
        trigger: ["blur", "change"],
      },
    ],
    phonenumber: [
      {
        pattern: /^1[3|4|5|6|7|8|9][0-9]\d{8}$/,
        message: "请输入正确的手机号码",
        trigger: "blur",
      },
    ],
  },
});

const { queryParams, form, rules } = toRefs(data);

onMounted(() => {
  calculateHeight();
  window.addEventListener("resize", calculateHeight);
});

const calculateHeight = () => {
  contentHeight.value =
    document.documentElement.clientHeight - searchRef.value?.offsetHeight - 220;
};

/** 通过条件过滤节点  */
const filterNode = (value, data) => {
  if (!value) return true;
  return data.label.indexOf(value) !== -1;
};
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
/** 查询用户列表 */
function getList() {
  loading.value = true;
  listUser(proxy.addDateRange(queryParams.value, dateRange.value)).then(
    (res) => {
      loading.value = false;
      userList.value = res.rows;
      total.value = res.total;
    }
  );
}
/** 节点单击事件 */
function handleNodeClick(data) {
  queryParams.value.deptId = data.id;
  handleQuery();
}
/** 搜索按钮操作 */
function handleQuery() {
  queryParams.value.pageNum = 1;
  getList();
}
/** 重置按钮操作 */
function resetQuery() {
  dateRange.value = [];
  proxy.resetForm("queryRef");
  queryParams.value.deptId = undefined;
  proxy.$refs.deptTreeRef.setCurrentKey(null);
  handleQuery();
}
/** 删除按钮操作 */
function handleDelete(row) {
  const userIds = row.userId || ids.value;
  proxy.$modal
    .confirm('是否确认删除用户编号为"' + userIds + '"的数据项？')
    .then(function () {
      return delUser(userIds);
    })
    .then(() => {
      getList();
      proxy.$modal.msgSuccess("删除成功");
    })
    .catch(() => {});
}
/** 导出按钮操作 */
function handleExport() {
  proxy.download(
    "system/user/export",
    {
      ...queryParams.value,
    },
    `user_${new Date().getTime()}.xlsx`
  );
}
/** 用户状态修改  */
function handleStatusChange(row) {
  let text = row.status === "0" ? "启用" : "停用";
  proxy.$modal
    .confirm('确认要"' + text + '""' + row.userName + '"用户吗?')
    .then(function () {
      return changeUserStatus(row.userId, row.status);
    })
    .then(() => {
      proxy.$modal.msgSuccess(text + "成功");
    })
    .catch(function () {
      row.status = row.status === "0" ? "1" : "0";
    });
}
/** 更多操作 */
function handleCommand(command, row) {
  switch (command) {
    case "handleResetPwd":
      handleResetPwd(row);
      break;
    case "handleAuthRole":
      handleAuthRole(row);
      break;
    default:
      break;
  }
}
/** 跳转角色分配 */
function handleAuthRole(row) {
  const userId = row.userId;
  router.push("/system/user-auth/role/" + userId);
}
/** 重置密码校验函数 */
function validateResetPassword(value, userName) {
  if (!value) {
    return "用户密码不能为空";
  }
  if (value.length < 8) {
    return "密码长度不能少于8位";
  }
  if (value.length > 20) {
    return "密码长度不能超过20位";
  }
  let typeCount = 0;
  if (/\d/.test(value)) typeCount++;
  if (/[a-z]/.test(value)) typeCount++;
  if (/[A-Z]/.test(value)) typeCount++;
  if (/[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>\/?]/.test(value)) typeCount++;
  if (typeCount < 3) {
    return "密码应至少包含数字、大小写字母及特殊字符中的三种";
  }
  const charCounts = {};
  for (const char of value) {
    charCounts[char] = (charCounts[char] || 0) + 1;
    if (charCounts[char] > value.length / 2) {
      return "禁止使用过多相同的数字或字符作为密码";
    }
  }
  for (let i = 0; i < value.length - 2; i++) {
    const c1 = value.charCodeAt(i);
    const c2 = value.charCodeAt(i + 1);
    const c3 = value.charCodeAt(i + 2);
    if (c1 >= 48 && c1 <= 57 && c2 >= 48 && c2 <= 57 && c3 >= 48 && c3 <= 57) {
      if ((c2 === c1 + 1 && c3 === c2 + 1) || (c2 === c1 - 1 && c3 === c2 - 1)) {
        return "禁止使用连续升序或降序的数字作为密码";
      }
    }
    if (c1 >= 65 && c1 <= 90 && c2 >= 65 && c2 <= 90 && c3 >= 65 && c3 <= 90) {
      if ((c2 === c1 + 1 && c3 === c2 + 1) || (c2 === c1 - 1 && c3 === c2 - 1)) {
        return "禁止使用连续升序或降序的字母作为密码";
      }
    }
    if (c1 >= 97 && c1 <= 122 && c2 >= 97 && c2 <= 122 && c3 >= 97 && c3 <= 122) {
      if ((c2 === c1 + 1 && c3 === c2 + 1) || (c2 === c1 - 1 && c3 === c2 - 1)) {
        return "禁止使用连续升序或降序的字母作为密码";
      }
    }
  }
  if (userName && value.toLowerCase() === userName.toLowerCase()) {
    return "禁止使用用户账户号作为密码";
  }
  return true;
}

/** 重置密码按钮操作 */
function handleResetPwd(row) {
  ElMessageBox
    .prompt('请输入"' + row.userName + '"的新密码', "提示", {
      confirmButtonText: "确定",
      cancelButtonText: "取消",
      closeOnClickModal: false,
      inputValidator: (value) => validateResetPassword(value, row.userName),
    })
    .then(({ value }) => {
      resetUserPwd(row.userId, value).then((response) => {
        proxy.$modal.msgSuccess("修改成功，新密码是：" + value);
      });
    })
    .catch(() => {});
}
/** 选择条数  */
function handleSelectionChange(selection) {
  ids.value = selection.map((item) => item.userId);
  single.value = selection.length != 1;
  multiple.value = !selection.length;
}
/** 导入按钮操作 */
function handleImport() {
  upload.title = "用户导入";
  upload.open = true;
}
/** 下载模板操作 */
function importTemplate() {
  proxy.download(
    "system/user/importTemplate",
    {},
    `user_template_${new Date().getTime()}.xlsx`
  );
}
/**文件上传中处理 */
const handleFileUploadProgress = (event, file, fileList) => {
  upload.isUploading = true;
};
/** 文件上传成功处理 */
const handleFileSuccess = (response, file, fileList) => {
  upload.open = false;
  upload.isUploading = false;
  proxy.$refs["uploadRef"].handleRemove(file);
  proxy.$alert(
    "<div style='overflow: auto;overflow-x: hidden;max-height: 70vh;padding: 10px 20px 0;'>" +
      response.msg +
      "</div>",
    "导入结果",
    { dangerouslyUseHTMLString: true }
  );
  getList();
};
/** 提交上传文件 */
function submitFileForm() {
  proxy.$refs["uploadRef"].submit();
}
/** 重置操作表单 */
function reset() {
  form.value = {
    userId: undefined,
    deptId: undefined,
    userName: undefined,
    nickName: undefined,
    password: undefined,
    phonenumber: undefined,
    email: undefined,
    sex: undefined,
    status: "0",
    remark: undefined,
    postIds: [],
    roleIds: [],
    assistGroup: [],
  };
  proxy.resetForm("userRef");
}
/** 取消按钮 */
function cancel() {
  open.value = false;
  reset();
}
/** 新增按钮操作 */
function handleAdd() {
  reset();
  getUser().then((response) => {
    postOptions.value = response.posts;
    roleOptions.value = response.roles;
    open.value = true;
    title.value = "添加用户";
    form.value.password = initPassword.value;
  });
}
/** 修改按钮操作 */
function handleUpdate(row) {
  reset();
  const userId = row.userId || ids.value;
  getUser(userId).then((response) => {
    const { data, postIds, roleIds } = response;

    form.value = {
      ...data,
      postIds,
      roleIds,
      assistGroup: data.assistGroup ? data.assistGroup.split(",") : [],
      password: "",
    };

    postOptions.value = response.posts;
    roleOptions.value = response.roles;

    open.value = true;
    title.value = "修改用户";
  });
}
/** 提交按钮 */
function submitForm() {
  proxy.$refs["userRef"].validate((valid) => {
    if (valid) {
      form.value.assistGroup = form.value.assistGroup.join(",");
      if (form.value.userId != undefined) {
        updateUser(form.value).then((response) => {
          proxy.$modal.msgSuccess("修改成功");
          open.value = false;
          getList();
        });
      } else {
        addUser(form.value).then((response) => {
          proxy.$modal.msgSuccess("新增成功");
          open.value = false;
          getList();
        });
      }
    }
  });
}
getDeptTree();
getList();
</script>
<style lang="scss" scoped>
.pg-container {
  align-items: center;

  .pagination-container {
    margin-bottom: 18px;
    margin-top: 15px;
    padding: 0 !important;
    background-color: transparent;
  }
}

#map {
  height: 100px;
}

.password-rule {
  margin: 0;
  padding: 16px 10px;
  line-height: 22px;
  border-radius: 4px;
  font-weight: 400;
  background-color: var(--color-warning-bg);
  color: var(--color-warning);
  list-style: none;

  .password-rule-title {
    margin-bottom: 8px;
  }

  // .password-rule-item {
  //   margin-left: 10px;
  // }
}
</style>
