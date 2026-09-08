/**
 * 适用于一个按钮，点击之后调用接口
 * 暴露的loading属性，用于控制loading状态
 *
 * 返回的run方法类型注释跟随传入的接口方法而来
 *
 */

import { Ref, ref } from 'vue'
import { TApiFun } from './type'
interface AutoRequestOptions {
  loading?: boolean
  onSuccess?: (data: any) => void
}

type AutoRequestResult<TData, TParams extends Array<any>> = [
  Ref<boolean>,
  TApiFun<TData, TParams>
]

/* 控制loading状态的自动切换hook */
export function useAutoRequest<TData, TParams extends any[] = any[]>(
  fun: TApiFun<TData, TParams>,
  options?: AutoRequestOptions
): AutoRequestResult<TData, TParams> {
  const { loading = false, onSuccess } = options || { loading: false }

  const requestLoading = ref(loading)

  const run: TApiFun<TData, TParams> = (...params) => {
    requestLoading.value = true
    return fun(...params)
      .then(res => {
        onSuccess && onSuccess(res)
        return res
      })
      .finally(() => {
        requestLoading.value = false
      })
  }

  return [requestLoading, run]
}

type AutoLoadingResult = [
  Ref<boolean>,
  <T>(requestPromise: Promise<T>) => Promise<T>
]

/* 在给run方法传入一个promise，会在promise执行前或执行后将loading状态设为true，在执行完成后设为false */
export function useAutoLoading(defaultLoading = false): AutoLoadingResult {
  const ld = ref(defaultLoading)

  function run<T>(requestPromise: Promise<T>): Promise<T> {
    ld.value = true
    return requestPromise.finally(() => {
      ld.value = false
    })
  }

  return [ld, run]
}
