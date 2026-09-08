import { onMounted, reactive, ref } from "vue";
import { hookResult } from "./bindResult";
import { ElMessageBox } from "element-plus";
interface PaginationTableProps {
  currentPage?: number;
  pageSize?: number;
  /* 在页面挂载时自动调用接口查询 */
  queryInMount?: boolean;
  apiFun: (params: any) => Promise<any>;
  transformData?: (data: any) => any;
  getQueryParams?: () => any;
  onDelete?: (row: any) => Promise<any>;
  insertIndex?: boolean;
}

export function usePaginationTable(prop: PaginationTableProps) {
  const {
    queryInMount = true,
    apiFun,
    currentPage = 1,
    pageSize = 10,
    transformData,
    getQueryParams,
    onDelete,
    insertIndex = false,
  } = prop;

  const loading = ref(false);

  const errorMsg = ref("");

  const dataSource = ref([]);

  const paginationData = reactive({
    currentPage: currentPage,
    pageSize: pageSize,
    total: 0,
    background: true,
    layout: "prev, pager, next, sizes, total",
  });

  function queryTableData(pagination?: {
    pageSize: number;
    currentPage: number;
  }) {
    const currentPaginationData = pagination || paginationData;

    let queryParams = {
      pageNum: currentPaginationData.currentPage,
      pageSize: currentPaginationData.pageSize,
    };
    if (getQueryParams) {
      const otherParams = getQueryParams();
      queryParams = {
        ...queryParams,
        ...otherParams,
      };
    }
    loading.value = true;
    return apiFun(queryParams)
      .then((result) => {
        if (result.code === 200) {
          if (transformData) {
            dataSource.value = transformData(result.rows);
          } else {
            dataSource.value = result.rows;
          }

          if (insertIndex) {
            dataSource.value.forEach((item, index) => {
              item._index =
                index +
                1 +
                (currentPaginationData.currentPage - 1) *
                  currentPaginationData.pageSize;
            });
          }

          if (dataSource.value.length === 0) {
            errorMsg.value = "暂无数据";
          }
          paginationData.total = result.total;
          paginationData.currentPage = queryParams.pageNum;
          paginationData.pageSize = queryParams.pageSize;
          return result;
        } else {
          return Promise.reject(new Error(result.msg));
        }
      })
      .catch((err) => {
        console.error("err", err);
        dataSource.value = [];
        errorMsg.value = err.message;
      })
      .finally(() => {
        loading.value = false;
      });
  }

  function onChange(pagination: any) {
    // console.log('pagination', pagination)
    // paginationData.currentPage = pagination.currentPage
    // paginationData.pageSize = pagination.pageSize
    queryTableData(pagination);
  }

  onMounted(() => {
    if (queryInMount) {
      queryTableData();
    }
  });

  function resetPage() {
    paginationData.currentPage = 1;
    paginationData.pageSize = pageSize;
  }

  function reload() {
    resetPage();
    return queryTableData();
  }

  function deleteRecord(row) {
    return ElMessageBox.alert("确认删除这条记录吗", "提醒", {
      confirmButtonText: "确认",
      cancelButtonText: "取消",
      showCancelButton: true,
      beforeClose: (action, instance, done) => {
        if (action === "confirm") {
          instance.confirmButtonLoading = true;
          instance.confirmButtonText = "删除中...";
          onDelete(row)
            .then(() => {
              done();
              reload();
            })
            .finally(() => {
              instance.confirmButtonLoading = false;
              instance.confirmButtonText = "确认";
            });
        } else {
          done();
        }
      },
    });
  }

  return hookResult(
    {
      execute: queryTableData,
      refresh: queryTableData,
      resetPage,
      reload,
      loading,
      deleteRecord,
    },
    {
      loading,
      pagination: paginationData,
      data: dataSource,
      emptyText: errorMsg,
      onChange: onChange,
    }
  );
}
