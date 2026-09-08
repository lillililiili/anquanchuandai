import { EditModalProps, useModalHandler } from './useModalHandler'

export function useModeModalHandler(props: EditModalProps = {}) {
  const modalHandler = useModalHandler(props)

  function showEdit(record) {
    return modalHandler.showModal('edit', record)
  }

  function showAdd(record?: any) {
    return modalHandler.showModal('add', record)
  }

  function showDetail(record?: any) {
    return modalHandler.showModal('detail', record)
  }

  return {
    ...modalHandler,
    showDetail,
    showAdd,
    showEdit
  }
}
