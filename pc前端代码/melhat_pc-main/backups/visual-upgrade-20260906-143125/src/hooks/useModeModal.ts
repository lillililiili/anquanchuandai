import { computed, ref, Ref, UnwrapRef } from 'vue'
import { hookResult } from './bindResult'

type UnionType<T> = T extends readonly any[] ? T[number] : T

export interface ModeModalProps<T extends readonly string[]> {
  modes: T

  /* 在modal中显示loading，自动控制 */
  modalLoading?: boolean

  onShow?: (mode: UnionType<T>, otherParams?: any) => void | Promise<void>

  onHide?: (mode: UnionType<T>) => void

  onSuccess?: (mode: UnionType<T>, res: any) => void

  renderTitle?: (mode: UnionType<T>) => string

  onOkClick?: (mode: UnionType<T>) => Promise<any> | any

  onCancelClick?: (mode: UnionType<T>) => Promise<any> | any

  okText?: string

  onCustomAction?: (mode: UnionType<T>, action: string) => Promise<any> | any
}

export interface ModeModalResult<T> {
  showModal: (mode: UnionType<T>, otherParams?: any) => void

  visible: Ref<boolean>

  currentShowMode: Ref<UnwrapRef<UnionType<T>>>

  isShow: (val: UnionType<T>) => boolean

  hideModal: () => void

  bindProps: any

  triggerOk: () => void

  triggerCancel: () => void

  expose: {
    showModal: (mode: UnionType<T>, otherParams?: any) => void
  }
}

export function useModeModal<T extends readonly string[]>(
  props: ModeModalProps<T>
): ModeModalResult<T> {
  const {
    modalLoading = false,
    modes,
    onShow,
    renderTitle,
    onOkClick,
    onHide,
    okText = '确认',
    onSuccess,
    onCancelClick
  } = props

  const currentShowMode = ref<UnionType<T>>(modes[0] as any)

  const dialogVisible = ref<boolean>(false)

  const okLoading = ref(false)

  const cancelLoading = ref(false)

  const openLoading = ref(false)

  const showModal: ModeModalResult<typeof modes>['showModal'] = (
    mode: UnionType<T>,
    otherParams?: any
  ) => {
    // @ts-ignore
    if (modes.includes(mode)) {
      if (onShow) {
        if (modalLoading) {
          openLoading.value = true
          currentShowMode.value = mode
          dialogVisible.value = true
        }

        return Promise.resolve(onShow(mode, otherParams))
          .then(() => {
            if (!modalLoading) {
              // @ts-ignore
              currentShowMode.value = mode
              dialogVisible.value = true
            }
          })
          .finally(() => {
            if (modalLoading) {
              openLoading.value = false
            }
          })
      } else {
        // @ts-ignore
        currentShowMode.value = mode
        dialogVisible.value = true
        return Promise.resolve()
      }
    }
    return Promise.reject(new Error('不存在mode:' + mode))
  }

  const hideModal = () => {
    // @ts-ignore
    onHide && onHide(currentShowMode.value)
    dialogVisible.value = false
  }

  const modalTitle = computed(() => {
    // @ts-ignore
    return renderTitle ? renderTitle(currentShowMode.value) : undefined
  })

  const onOk = () => {
    if (onOkClick) {
      okLoading.value = true
      // @ts-ignore
      Promise.resolve(onOkClick(currentShowMode.value))
        .then(res => {
          onSuccess && onSuccess(currentShowMode.value, res)
          hideModal()
        })
        .finally(() => {
          okLoading.value = false
        })
    } else {
      hideModal()
    }
  }

  const onCancel = () => {
    if (onCancelClick) {
      cancelLoading.value = true
      // @ts-ignore
      Promise.resolve(onCancelClick(currentShowMode.value))
        .then(res => {
          onSuccess && onSuccess(currentShowMode.value, res)
          hideModal()
        })
        .finally(() => {
          cancelLoading.value = false
        })
    } else {
      hideModal()
    }
  }

  const closable = computed(() => {
    return !okLoading.value
  })

  function isShow(val: UnionType<T>) {
    return currentShowMode.value === val
  }

  return hookResult(
    {
      visible: dialogVisible,
      currentShowMode,
      isShow,
      showModal,
      hideModal,
      triggerOk: onOk,
      triggerCancel: onCancel,
      expose: {
        showModal
      }
    },
    {
      modelValue: dialogVisible,
      title: modalTitle,
      closable: closable,
      okText: okText,
      loading: openLoading,
      okLoading: okLoading,
      cancelLoading: cancelLoading,
      onOk: onOk,
      onCancel: onCancel
    }
  )
}
