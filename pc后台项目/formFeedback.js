import { computed, nextTick, ref, watch } from 'vue'

// Keep validation next to its field; reserve the footer for non-field failures.
export function useFormFeedback(form, errorSource, prefix, aliases = {}) {
  const formRef = ref(null), localErrors = ref({}), remoteErrors = ref({})
  const errors = computed(() => ({ ...remoteErrors.value, ...localErrors.value }))
  const formError = computed(() => {
    const error = errorSource()
    if (!error) return ''
    const known = new Set([...Object.keys(form.value).map(key => aliases[key] || key), ...Object.values(aliases)])
    const unmapped = Object.entries(remoteErrors.value).filter(([key]) => !known.has(key))
    if (unmapped.length) return unmapped.map(([, message]) => message).join('；')
    return Object.keys(error.fields || {}).length ? '' : (error.message || '保存失败，请稍后重试。')
  })
  async function focusErrors() {
    await nextTick()
    const root = formRef.value
    if (!root) return
    const ids = new Set(Object.keys(errors.value).map(key => prefix + key))
    const field = [...root.querySelectorAll('[id]')].find(el => ids.has(el.id))
    const control = field?.matches('input:not([type="hidden"]):not(.ui-native-proxy), textarea, select:not(.ui-native-proxy), button')
      ? field : field?.querySelector('[role="combobox"], input:not([type="hidden"]):not(.ui-native-proxy), textarea, button') || field
    const target = control || root.querySelector('[data-form-error]')
    if (target && !target.hasAttribute('tabindex') && !target.matches('input, textarea, select, button')) target.tabIndex = -1
    target?.focus()
    target?.scrollIntoView({ block: 'nearest' })
  }
  watch(errorSource, error => {
    remoteErrors.value = Object.fromEntries(Object.entries(error?.fields || {}).map(([key, message]) => {
      const field = key.split(/[.\[]/)[0]
      return [aliases[field] || field, message]
    }))
    if (error) focusErrors()
  }, { immediate: true })
  let previous = JSON.parse(JSON.stringify(form.value))
  watch(form, value => {
    for (const key of new Set([...Object.keys(value), ...Object.keys(previous)])) {
      if (JSON.stringify(value[key]) === JSON.stringify(previous[key])) continue
      const field = aliases[key] || key
      delete localErrors.value[field]
      delete remoteErrors.value[field]
    }
    previous = JSON.parse(JSON.stringify(value))
  }, { deep: true, flush: 'sync' })
  return { formRef, localErrors, errors, formError, focusErrors }
}
