import { shallowRef, onUnmounted, ref } from 'vue'
import { hookResult } from './bindResult'
export interface EditModalProps {
  onSuccess?: () => void
}

export function useModalHandler(props: EditModalProps = {}) {
  const { onSuccess } = props

  const modalRef = shallowRef()
  // 添加 visible 状态，用于控制组件是否渲染
  const visible = ref(false)

  function setRef(el) {
    modalRef.value = el
  }

  onUnmounted(() => {
    modalRef.value = null
  })

  function returnVerifyRef(method: (instance: any) => Promise<any>) {
    if (modalRef.value) {
      return method(modalRef.value)
    } else {
      return Promise.reject(new Error('弹窗modalRef为null'))
    }
  }

  function showModal(...params: any[]) {
    visible.value = true // 显示时标记为可见
    return returnVerifyRef(r => {
      return r.showModal(...params)
    })
  }

  function hideModal() {
    visible.value = false
  }

  function onModalSuccess(...args) {
    onSuccess && onSuccess(...args)
  }

  return hookResult(
    {
      showModal,
      hideModal,
      visible
    },
    {
      ref: setRef,
      onSuccess: onModalSuccess
    }
  )
}
