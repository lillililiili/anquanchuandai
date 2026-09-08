<template>
    <div class="app-container">
        <el-form :model="queryParams" ref="queryRef" :inline="true" v-show="showSearch" label-width="68px">
                        <el-form-item label="设备id" prop="devicesId">
                            <el-input
                                    v-model="queryParams.devicesId"
                                    placeholder="请输入设备id"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="设备编号" prop="devicesNumber">
                            <el-input
                                    v-model="queryParams.devicesNumber"
                                    placeholder="请输入设备编号"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="开始时间" prop="statrtTime">
                            <el-date-picker clearable
                                            v-model="queryParams.statrtTime"
                                            type="date"
                                            value-format="YYYY-MM-DD"
                                            placeholder="请选择开始时间">
                            </el-date-picker>
                        </el-form-item>
                        <el-form-item label="结束时间" prop="endTime">
                            <el-date-picker clearable
                                            v-model="queryParams.endTime"
                                            type="date"
                                            value-format="YYYY-MM-DD"
                                            placeholder="请选择结束时间">
                            </el-date-picker>
                        </el-form-item>
                        <el-form-item label="报警信息" prop="sosMessge">
                            <el-input
                                    v-model="queryParams.sosMessge"
                                    placeholder="请输入报警信息"
                                    clearable
                                    @keyup.enter="handleQuery"
                            />
                        </el-form-item>
                        <el-form-item label="报警位置" prop="sosPosition">
                            <el-input
                                    v-model="queryParams.sosPosition"
                                    placeholder="请输入报警位置"
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
                        v-hasPermi="['system:sos:add']"
                >新增</el-button>
            </el-col>
            <el-col :span="1.5">
                <el-button
                        type="success"
                        plain
                        icon="Edit"
                        :disabled="single"
                        @click="handleUpdate"
                        v-hasPermi="['system:sos:edit']"
                >修改</el-button>
            </el-col>
            <el-col :span="1.5">
                <el-button
                        type="danger"
                        plain
                        icon="Delete"
                        :disabled="multiple"
                        @click="handleDelete"
                        v-hasPermi="['system:sos:remove']"
                >删除</el-button>
            </el-col>
            <el-col :span="1.5">
                <el-button
                        type="warning"
                        plain
                        icon="Download"
                        @click="handleExport"
                        v-hasPermi="['system:sos:export']"
                >导出</el-button>
            </el-col>
            <right-toolbar v-model:showSearch="showSearch" @queryTable="getList"></right-toolbar>
        </el-row>

        <el-table v-loading="loading" :data="sosList" @selection-change="handleSelectionChange">
            <el-table-column type="selection" width="55" align="center" />
                    <el-table-column label="主键id" align="center" prop="id" />
                    <el-table-column label="设备id" align="center" prop="devicesId" />
                    <el-table-column label="设备编号" align="center" prop="devicesNumber" />
                    <el-table-column label="设备状态('0->报警'1->'未报警')" align="center" prop="devicesStatus" />
                    <el-table-column label="开始时间" align="center" prop="statrtTime" width="180">
                        <template #default="scope">
                            <span>{{ parseTime(scope.row.statrtTime, '{y}-{m}-{d}') }}</span>
                        </template>
                    </el-table-column>
                    <el-table-column label="结束时间" align="center" prop="endTime" width="180">
                        <template #default="scope">
                            <span>{{ parseTime(scope.row.endTime, '{y}-{m}-{d}') }}</span>
                        </template>
                    </el-table-column>
                    <el-table-column label="报警类型('0->sos'1->'脱帽'2->'违章')" align="center" prop="sosType" />
                    <el-table-column label="报警信息" align="center" prop="sosMessge" />
                    <el-table-column label="报警位置" align="center" prop="sosPosition" />
            <el-table-column label="操作" align="center" class-name="small-padding fixed-width">
                <template #default="scope">
                    <el-button link type="primary" icon="Edit" @click="handleUpdate(scope.row)" v-hasPermi="['system:sos:edit']">修改</el-button>
                    <el-button link type="primary" icon="Delete" @click="handleDelete(scope.row)" v-hasPermi="['system:sos:remove']">删除</el-button>
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

        <!-- 添加或修改报警对话框 -->
        <el-dialog :title="title" v-model="open" width="500px" append-to-body>
            <el-form ref="sosRef" :model="form" :rules="rules" label-width="80px">
                                <el-form-item label="设备id" prop="devicesId">
                                    <el-input v-model="form.devicesId" placeholder="请输入设备id" />
                                </el-form-item>
                                <el-form-item label="设备编号" prop="devicesNumber">
                                    <el-input v-model="form.devicesNumber" placeholder="请输入设备编号" />
                                </el-form-item>
                                <el-form-item label="开始时间" prop="statrtTime">
                                    <el-date-picker clearable
                                                    v-model="form.statrtTime"
                                                    type="date"
                                                    value-format="YYYY-MM-DD"
                                                    placeholder="请选择开始时间">
                                    </el-date-picker>
                                </el-form-item>
                                <el-form-item label="结束时间" prop="endTime">
                                    <el-date-picker clearable
                                                    v-model="form.endTime"
                                                    type="date"
                                                    value-format="YYYY-MM-DD"
                                                    placeholder="请选择结束时间">
                                    </el-date-picker>
                                </el-form-item>
                                <el-form-item label="报警信息" prop="sosMessge">
                                    <el-input v-model="form.sosMessge" placeholder="请输入报警信息" />
                                </el-form-item>
                                <el-form-item label="报警位置" prop="sosPosition">
                                    <el-input v-model="form.sosPosition" placeholder="请输入报警位置" />
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

<script setup name="Sos">
    import { listSos, getSos, delSos, addSos, updateSos } from "@/api/system/sos";

    const { proxy } = getCurrentInstance();

    const sosList = ref([]);
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
                        devicesId: null,
                        devicesNumber: null,
                        devicesStatus: null,
                        statrtTime: null,
                        endTime: null,
                        sosType: null,
                        sosMessge: null,
                        sosPosition: null,
        },
        rules: {
                        devicesId: [
                        { required: true, message: "设备id不能为空", trigger: "blur" }
                    ],
        }
    });

    const { queryParams, form, rules } = toRefs(data);

    /** 查询报警列表 */
    function getList() {
        loading.value = true;
        listSos(queryParams.value).then(response => {
                sosList.value = response.rows;
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
                        devicesId: null,
                        devicesNumber: null,
                        devicesStatus: null,
                        statrtTime: null,
                        endTime: null,
                        sosType: null,
                        sosMessge: null,
                        sosPosition: null,
                        delFlag: null,
                        createTime: null,
                        updateTime: null,
                        createBy: null,
                        updateBy: null
        };
        proxy.resetForm("sosRef");
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
        title.value = "添加报警";
    }

    /** 修改按钮操作 */
    function handleUpdate(row) {
        reset();
        const _id = row.id || ids.value
        getSos(_id).then(response => {
            form.value = response.data;
            open.value = true;
            title.value = "修改报警";
        });
    }

    /** 提交按钮 */
    function submitForm() {
        proxy.$refs["sosRef"].validate(valid => {
            if (valid) {
                if (form.value.id != null) {
                    updateSos(form.value).then(response => {
                        proxy.$modal.msgSuccess("修改成功");
                        open.value = false;
                        getList();
                    });
                } else {
                    addSos(form.value).then(response => {
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
        proxy.$modal.confirm('是否确认删除报警编号为"' + _ids + '"的数据项？').then(function() {
            return delSos(_ids);
        }).then(() => {
            getList();
            proxy.$modal.msgSuccess("删除成功");
        }).catch(() => {});
    }

    /** 导出按钮操作 */
    function handleExport() {
        proxy.download('system/sos/export', {
            ...queryParams.value
        }, `sos_${new Date().getTime()}.xlsx`)
    }

    getList();
</script>