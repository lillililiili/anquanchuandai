import { nextTick } from 'vue'
import { useFormItem } from 'element-plus'

//  触发el-form-item的校验事件 trigger
export function useTrigger() {
  const { formItem } = useFormItem() // form formItem
  const emitTrigger = () => {
    if (formItem) {
      nextTick(() => {
        formItem.validate('blur') // 触发校验
        formItem.validate('change') // 触发校验
      })
    }
  }
  return { formItem, emitTrigger }
}
