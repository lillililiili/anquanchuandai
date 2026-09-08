import { ElMessageBox } from 'element-plus'

interface ConfirmProps {
  onConfirm: () => Promise<any | void>
  title?: string
  msg: string
  confirmButtonText?: string
  cancelButtonText?: string
  confirmLoadingText?: string
}

export function showConfirm(props: ConfirmProps) {
  const {
    onConfirm,
    title = '提醒',
    msg,
    confirmButtonText = '确认',
    cancelButtonText = '取消',
    confirmLoadingText = '确认中...'
  } = props

  return ElMessageBox.alert(msg, title, {
    confirmButtonText: confirmButtonText,
    cancelButtonText: cancelButtonText,
    showCancelButton: true,
    beforeClose: (action, instance, done) => {
      if (action === 'confirm') {
        instance.confirmButtonLoading = true
        instance.confirmButtonText = confirmLoadingText
        onConfirm()
          .then(() => {
            done()
          })
          .finally(() => {
            instance.confirmButtonLoading = false
            instance.confirmButtonText = confirmButtonText
          })
      } else {
        done()
      }
    }
  })
}
