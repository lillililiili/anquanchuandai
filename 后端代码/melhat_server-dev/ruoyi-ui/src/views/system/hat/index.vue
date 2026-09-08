<template>
    <div class="app-container">
        <el-form :model="queryParams" ref="queryRef" :inline="true" v-show="showSearch" label-width="68px">
                        <el-form-item label="人员id" prop="userId">
                            <el-input
                                    v-model="queryParams.userId"
                                    placeholder="请输入人员id"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="姓名" prop="name">
                            <el-input
                                    v-model="queryParams.name"
                                    placeholder="请输入姓名"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="部门id" prop="deptId">
                            <el-input
                                    v-model="queryParams.deptId"
                                    placeholder="请输入部门id"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="部门" prop="section">
                            <el-input
                                    v-model="queryParams.section"
                                    placeholder="请输入部门"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="职位" prop="position">
                            <el-input
                                    v-model="queryParams.position"
                                    placeholder="请输入职位"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="SIM卡号" prop="simNumber">
                            <el-input
                                    v-model="queryParams.simNumber"
                                    placeholder="请输入SIM卡号"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="所在分组" prop="inGroup">
                            <el-input
                                    v-model="queryParams.inGroup"
                                    placeholder="请输入所在分组"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="手机号码" prop="phone">
                            <el-input
                                    v-model="queryParams.phone"
                                    placeholder="请输入手机号码"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="APP密码" prop="password">
                            <el-input
                                    v-model="queryParams.password"
                                    placeholder="请输入APP密码"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="设备编号" prop="deviceNumber">
                            <el-input
                                    v-model="queryParams.deviceNumber"
                                    placeholder="请输入设备编号"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
            <el-form-item>
                <el-button type="primary" icon="Search" @click="handleQuery">搜索</el-button>
                <el-button icon="Refresh" @click="resetQuery">重置</el-button>
            </el-form-item>
        </el-form>

        <el-row :gutter="10" class="mb8">
            <el-col :span="1.5">
                <el-button
                        type="primary"
                        plain
                        icon="Plus"
                        @click="handleAdd"
                        v-hasPermi="['system:hat:add']"
                >新增</el-button>
            </el-col>
            <el-col :span="1.5">
                <el-button
                        type="success"
                        plain
                        icon="Edit"
                        :disabled="single"
                        @click="handleUpdate"
                        v-hasPermi="['system:hat:edit']"
                >修改</el-button>
            </el-col>
            <el-col :span="1.5">
                <el-button
                        type="danger"
                        plain
                        icon="Delete"
                        :disabled="multiple"
                        @click="handleDelete"
                        v-hasPermi="['system:hat:remove']"
                >删除</el-button>
            </el-col>
            <el-col :span="1.5">
                <el-button
                        type="warning"
                        plain
                        icon="Download"
                        @click="handleExport"
                        v-hasPermi="['system:hat:export']"
                >导出</el-button>
            </el-col>
            <right-toolbar v-model:showSearch="showSearch" @queryTable="getList"></right-toolbar>
        </el-row>

        <el-table v-loading="loading" :data="hatList" @selection-change="handleSelectionChange">
            <el-table-column type="selection" width="55" align="center" />
                    <el-table-column label="主键id" align="center" prop="id" />
                    <el-table-column label="人员id" align="center" prop="userId" />
                    <el-table-column label="姓名" align="center" prop="name" />
                    <el-table-column label="部门id" align="center" prop="deptId" />
                    <el-table-column label="部门" align="center" prop="section" />
                    <el-table-column label="职位" align="center" prop="position" />
                    <el-table-column label="类型" align="center" prop="type" />
                    <el-table-column label="SIM卡号" align="center" prop="simNumber" />
                    <el-table-column label="所在分组" align="center" prop="inGroup" />
                    <el-table-column label="手机号码" align="center" prop="phone" />
                    <el-table-column label="APP密码" align="center" prop="password" />
                    <el-table-column label="设备编号" align="center" prop="deviceNumber" />
            <el-table-column label="操作" align="center" class-name="small-padding fixed-width">
                <template #default="scope">
                    <el-button link type="primary" icon="Edit" @click="handleUpdate(scope.row)" v-hasPermi="['system:hat:edit']">修改</el-button>
                    <el-button link type="primary" icon="Delete" @click="handleDelete(scope.row)" v-hasPermi="['system:hat:remove']">删除</el-button>
                </template>
            </el-table-column>
        </el-table>

        <pagination
                v-show="total>0"
                :total="total"
                v-model:page="queryParams.pageNum"
                v-model:limit="queryParams.pageSize"
                @pagination="getList"
        />

        <!-- 添加或修改安全帽对话框 -->
        <el-dialog :title="title" v-model="open" width="500px" append-to-body>
            <el-form ref="hatRef" :model="form" :rules="rules" label-width="80px">
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
    import { listHat, getHat, delHat, addHat, updateHat } from "@/api/system/hat";

    const { proxy } = getCurrentInstance();

    const hatList = ref([]);
    const open = ref(false);
    const loading = ref(true);
    const showSearch = ref(true);
    const ids = ref([]);
    const single = ref(true);
    const multiple = ref(true);
    const total = ref(0);
    const title = ref("");

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
        rules: {
        }
    });

    const { queryParams, form, rules } = toRefs(data);

    /** 查询安全帽列表 */
    function getList() {
        loading.value = true;
        listHat(queryParams.value).then(response => {
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
                        updateBy: null
        };
        proxy.resetForm("hatRef");
    }

    /** 搜索按钮操作 */
    function handleQuery() {
        queryParams.value.pageNum = 1;
        getList();
    }

    /** 重置按钮操作 */
    function resetQuery() {
        proxy.resetForm("queryRef");
        handleQuery();
    }

    // 多选框选中数据
    function handleSelectionChange(selection) {
        ids.value = selection.map(item => item.id);
        single.value = selection.length != 1;
        multiple.value = !selection.length;
    }

    /** 新增按钮操作 */
    function handleAdd() {
        reset();
        open.value = true;
        title.value = "添加安全帽";
    }

    /** 修改按钮操作 */
    function handleUpdate(row) {
        reset();
        const _id = row.id || ids.value
        getHat(_id).then(response => {
            form.value = response.data;
            open.value = true;
            title.value = "修改安全帽";
        });
    }

    /** 提交按钮 */
    function submitForm() {
        proxy.$refs["hatRef"].validate(valid => {
            if (valid) {
                if (form.value.id != null) {
                    updateHat(form.value).then(response => {
                        proxy.$modal.msgSuccess("修改成功");
                        open.value = false;
                        getList();
                    });
                } else {
                    addHat(form.value).then(response => {
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
        const _ids = row.id || ids.value;
        proxy.$modal.confirm('是否确认删除安全帽编号为"' + _ids + '"的数据项？').then(function() {
            return delHat(_ids);
        }).then(() => {
            getList();
            proxy.$modal.msgSuccess("删除成功");
        }).catch(() => {});
    }

    /** 导出按钮操作 */
    function handleExport() {
        proxy.download('system/hat/export', {
            ...queryParams.value
        }, `hat_${new Date().getTime()}.xlsx`)
    }

    getList();
</script>