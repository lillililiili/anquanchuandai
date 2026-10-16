import { nextTick, ref, watch } from 'vue'

export function validateNativeControls(root) {
  // Custom date/select controls cancel native invalid bubbles and render their
  // own field message. Keep their constraints active in novalidate forms.
  let valid = true
  for (const control of root?.querySelectorAll('.ui-native-proxy') || []) {
    if (!control.checkValidity()) valid = false
  }
  return valid
}

// Field rules remain with the business form; this only handles presentation.
export function useFieldErrors(values) {
  const formRef = ref(null), errors = ref({})
  function validate(messages) {
    errors.value = Object.fromEntries(Object.entries(messages).filter(([, message]) => message))
    const controlsValid = validateNativeControls(formRef.value)
    if (!Object.keys(errors.value).length) return controlsValid
    nextTick(() => {
      const field = [...(formRef.value?.querySelectorAll('[data-field]') || [])].find(el => errors.value[el.dataset.field])
      const control = field?.matches('input, textarea, select, button') ? field : field?.querySelector('input:not(.ui-native-proxy), textarea, [role="combobox"], button') || field
      if (control && !control.matches('input, textarea, select, button')) control.tabIndex = -1
      control?.focus()
      control?.scrollIntoView({ block: 'nearest' })
    })
    return false
  }
  let previous = JSON.parse(JSON.stringify(values()))
  watch(values, value => {
    for (const key of new Set([...Object.keys(previous), ...Object.keys(value)])) {
      if (JSON.stringify(previous[key]) !== JSON.stringify(value[key])) delete errors.value[key]
    }
    previous = JSON.parse(JSON.stringify(value))
  }, { deep: true, flush: 'sync' })
  return { formRef, errors, validate }
}
