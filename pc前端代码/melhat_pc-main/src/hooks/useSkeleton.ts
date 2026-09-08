import { TApiFun } from "./type";
import { computed, onMounted, reactive, ref, UnwrapRef } from "vue";
import SkeletonViewComponent from "@/components/Skeleton/index.vue";

export type SkeletonStatus = "loading" | "success";

export interface IUseAutoSkeletonViewProps<TData, TParams extends any[]> {
  apiFun: TApiFun<TData, TParams>;
  placeholderResult?: TData;
  queryInMount?: boolean;
  initQueryParams?: TParams;
  transformDataFun?: (data: TData) => TData;
  updateParamsOnFetch?: boolean;
  defaultStatus?: SkeletonStatus;
  initData?: TData;
  onSuccess?: (data: any) => void;
  onError?: (e: any) => void;
  isEmpty?: (data: any) => boolean;
  coverLoading?: boolean;
}

export const SkeletonView = SkeletonViewComponent;

// type UnwrapNestedRefs<T> = ReturnType<typeof reactive>;

export type IAutoSkeletonViewResult<TData, TParams extends any[]> = UnwrapRef<{
  execute: TApiFun<TData, TParams>;
  result: TData | null;
  retry: () => Promise<TData>;
  loading: boolean;
  status: SkeletonStatus | "error";
  getField: (key: string) => any;
  bindProps: {
    result: TData | null;
    status: SkeletonStatus | "error";
    errorMsg: string;
    placeholderResult?: TData;
    isEmpty?: (data: TData) => boolean;
    onRetry: () => Promise<TData>;
  };
}>;

export function useSkeleton<TData = any, TParams extends any[] = any[]>(
  prop: IUseAutoSkeletonViewProps<TData, TParams>
): IAutoSkeletonViewResult<TData, TParams> {
  const {
    coverLoading,
    apiFun,
    onError,
    defaultStatus = "loading",
    placeholderResult,
    isEmpty,
    initQueryParams = [],
    transformDataFun,
    onSuccess,
    initData = null,
    updateParamsOnFetch = true,
    queryInMount = true,
  } = prop;

  const status = ref<SkeletonStatus | "error">(defaultStatus);

  const result = ref<TData | null>(initData);

  const placeholder = ref<TData | undefined>(placeholderResult);

  const errorMsg = ref("");

  const lastFetchParams = ref<TParams>(initQueryParams as TParams);

  const executeApiFun: TApiFun<TData, TParams> = (...params: TParams) => {
    if (updateParamsOnFetch) {
      // @ts-ignore
      lastFetchParams.value = params;
    }

    status.value = "loading";

    return apiFun(...params)
      .then((res) => {
        // @ts-ignore
        let data: any = res.data;
        if (transformDataFun) {
          data = transformDataFun(data);
        }
        placeholder.value = data;
        result.value = data;
        status.value = "success";
        onSuccess && onSuccess(data);
        return res;
      })
      .catch((e) => {
        console.error("--useAutoSkeletonView--", e);
        status.value = "error";
        errorMsg.value = e.message;
        onError && onError(e);
        throw e;
      });
  };

  function retry() {
    return executeApiFun(...(lastFetchParams.value as TParams));
  }

  onMounted(() => {
    if (queryInMount && defaultStatus === "loading") {
      executeApiFun(...(initQueryParams as TParams));
    }
  });

  const loading = computed(() => {
    return status.value === "loading";
  });

  function getField(key: string) {
    if (status.value !== "success") {
      return "";
    }
    if (result.value) {
      return result.value[key];
    }
    return "";
  }

  return reactive({
    execute: executeApiFun,
    result: result,
    retry,
    loading,
    status,
    getField,
    bindProps: {
      result: result,
      status,
      errorMsg,
      placeholderResult: placeholder,
      isEmpty,
      coverLoading,
      onRetry: retry,
    },
  });
}
