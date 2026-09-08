import { Ref, computed, reactive, unref } from 'vue'

interface FakePaginationProps<T = any> {
  data: Ref<T[]> | T[]
  current?: number
  pageSize?: number
}

export function useFakePagination<T = any>(prop: FakePaginationProps<T>) {
  const { data } = prop

  const pageData = reactive({
    currentPage: 1,
    pageSize: 10,
    total: computed(() => unref(data).length),
    'onUpdate:currentPage': val => {
      pageData.currentPage = val
    },
    'onUpdate:pageSize': val => {
      pageData.pageSize = val
    }
  })

  const currentTableData = computed(() => {
    const startIndex = (pageData.currentPage - 1) * pageData.pageSize
    const endIndex = startIndex + pageData.pageSize
    return unref(data).slice(startIndex, endIndex + 1)
  })

  return [currentTableData, pageData]
}
