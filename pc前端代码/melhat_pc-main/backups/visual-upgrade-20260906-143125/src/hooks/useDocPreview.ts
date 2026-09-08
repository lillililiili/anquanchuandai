import { Ref, watch } from 'vue'
import { renderAsync } from 'docx-preview'

interface DocPreviewProp {
  container: Ref<HTMLDivElement>
  document?: Blob | ArrayBuffer | Uint8Array
}

export function useDocPreview(prop: DocPreviewProp) {
  const { container } = prop

  watch(container, newVal => {
    if (newVal) {
      render()
    }
  })

  function render(docData: Blob | ArrayBuffer | Uint8Array = prop.document) {
    if (!docData) return
    if (!container.value) return
    renderAsync(docData, container.value)
  }

  return [render]
}
