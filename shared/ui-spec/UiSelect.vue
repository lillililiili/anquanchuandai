<script setup>
import { computed, ref, shallowRef, useSlots, useAttrs, useId, nextTick, watch, onBeforeUpdate } from 'vue'
import UiIcon from './UiIcon.vue'
import { usePopup } from './usePopup'
import { useControlLabel } from './useControlLabel'
defineOptions({ inheritAttrs: false })
const props = defineProps({ modelValue: { default: undefined }, value: { default: undefined }, options: Array, multiple: Boolean, disabled: Boolean, required: Boolean, name: String, placeholder: { type: String, default: '请选择' } })
const emit = defineEmits(['update:modelValue', 'change', 'blur', 'focus'])
const slots = useSlots(), attrs = useAttrs(), uid = useId(), trigger = ref(null), native = ref(null), active = ref(-1), invalid = ref(false)
const { open, panel, target, position, show, close, toggle } = usePopup(trigger)
const controlLabel = useControlLabel(trigger)
const selected = computed(() => props.modelValue !== undefined ? props.modelValue : (props.value ?? (props.multiple ? [] : '')))
function text(nodes) { return Array.isArray(nodes) ? nodes.map(n => typeof n === 'object' ? text(n.children) : n).join('') : typeof nodes === 'string' ? nodes : '' }
function collect(nodes, result = [], disabled = false) {
  for (const n of nodes || []) {
    if (n.type === 'option') result.push({ value: n.props?.value ?? text(n.children), label: text(n.children), disabled: disabled || (n.props?.disabled !== undefined && n.props.disabled !== false) })
    else if (Array.isArray(n.children)) collect(n.children, result, disabled || (n.type === 'optgroup' && n.props?.disabled))
  }
  return result
}
// Slots themselves aren't reactive. Refresh before render when an async option list changes.
const slotItems = shallowRef(collect(slots.default?.()))
onBeforeUpdate(() => { const next = collect(slots.default?.()); if (JSON.stringify(next) !== JSON.stringify(slotItems.value)) slotItems.value = next })
const items = computed(() => props.options ? props.options.map(o => Array.isArray(o) ? { value: o[0], label: o[1] } : typeof o === 'object' ? o : { value: o, label: o }) : slotItems.value)
const same = (a, b) => String(a ?? '') === String(b ?? '')
const chosen = o => props.multiple ? (Array.isArray(selected.value) && selected.value.some(v => same(v, o.value))) : same(selected.value, o.value)
const label = computed(() => items.value.filter(chosen).map(o => o.label).join('、') || props.placeholder)
const labelledBy = computed(() => attrs['aria-labelledby'])
async function change(item) {
  if (!item || item.disabled || props.disabled) return
  const next = props.multiple ? (chosen(item) ? selected.value.filter(v => !same(v, item.value)) : [...(Array.isArray(selected.value) ? selected.value : []), item.value]) : item.value
  invalid.value = false
  emit('update:modelValue', next)
  // Preserve native change-event callers in both applications.
  await nextTick()
  if (native.value) {
    for (const option of native.value.options) option.selected = props.multiple ? next.some(v => same(v, option.value)) : same(next, option.value)
    native.value.dispatchEvent(new Event('change', { bubbles: true }))
  }
  if (!props.multiple) close(true)
}
function move(delta) {
  const enabled = items.value.map((o,i) => o.disabled ? -1 : i).filter(i => i >= 0)
  if (!enabled.length) return
  const at = enabled.indexOf(active.value); active.value = enabled[(at + delta + enabled.length) % enabled.length]
  nextTick(() => panel.value?.querySelector(`[data-option="${active.value}"]`)?.scrollIntoView({ block: 'nearest' }))
}
async function expand() { if (props.disabled) return; active.value = Math.max(0, items.value.findIndex(chosen)); await show() }
let typed = '', typedAt = 0
function keydown(e) {
  if (['ArrowDown','ArrowUp','Home','End','Enter',' '].includes(e.key)) {
    e.preventDefault()
    if (!open.value) { expand(); return }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') move(e.key === 'ArrowDown' ? 1 : -1)
    else if (e.key === 'Home') active.value = items.value.findIndex(o => !o.disabled)
    else if (e.key === 'End') active.value = items.value.findLastIndex(o => !o.disabled)
    else change(items.value[active.value])
  } else if (e.key === 'Tab') close()
  else if (e.key.length === 1 && !e.ctrlKey && !e.metaKey) {
    typed = Date.now() - typedAt > 700 ? e.key : typed + e.key; typedAt = Date.now()
    const i = items.value.findIndex(o => !o.disabled && String(o.label).toLowerCase().startsWith(typed.toLowerCase()))
    if (i >= 0) { active.value = i; if (!open.value) change(items.value[i]) }
  }
}
watch(() => props.disabled, v => { if (v) close() })
watch(selected, () => { invalid.value = false }, { deep: true })
defineExpose({ focus: () => trigger.value?.focus(), checkValidity: () => native.value?.checkValidity(), reportValidity: () => native.value?.reportValidity() })
</script>
<template>
  <span class="ui-select" :class="[attrs.class, { 'is-disabled': disabled, 'is-invalid': invalid }]" :style="attrs.style">
    <select ref="native" class="ui-native-proxy" :name="name" :multiple="multiple" :disabled="disabled" :required="required" tabindex="-1" aria-hidden="true" @focus="trigger?.focus()" @invalid.prevent="invalid = true; trigger?.focus()" @change="emit('change', $event)">
      <option v-for="(item, index) in items" :key="index" :value="item.value" :disabled="item.disabled" :selected="chosen(item)">{{ item.label }}</option>
    </select>
    <button ref="trigger" class="ui-select-trigger" type="button" role="combobox" :id="attrs.id" :disabled="disabled" :aria-label="attrs['aria-label'] || controlLabel || undefined" :aria-labelledby="labelledBy" :aria-describedby="[attrs['aria-describedby'], invalid ? uid + '-error' : ''].filter(Boolean).join(' ') || undefined" :aria-required="required || undefined" :aria-invalid="invalid || attrs['aria-invalid']" aria-haspopup="listbox" :aria-controls="uid" :aria-expanded="open" :aria-activedescendant="open && active >= 0 ? `${uid}-${active}` : undefined" @click="open ? close() : expand()" @keydown="keydown" @blur="emit('blur', $event)" @focus="emit('focus', $event)">
      <slot name="trigger" :label="label" :open="open"><span class="ui-select-value">{{ label }}</span><UiIcon name="chevron-down" /></slot>
    </button>
    <small v-if="invalid" :id="uid + '-error'" class="ui-control-error" aria-live="polite">请选择{{ attrs['aria-label'] || controlLabel || '选项' }}</small>
    <Teleport :to="target"><div v-if="open" :id="uid" ref="panel" class="ui-popup ui-select-popup" :style="position" role="listbox" :aria-label="attrs['aria-label'] || '选项'" :aria-multiselectable="multiple || undefined" @pointerdown.prevent>
      <div v-for="(item,index) in items" :key="index" :id="`${uid}-${index}`" class="ui-option" :class="{ selected: chosen(item), active: active === index, disabled: item.disabled }" :data-option="index" role="option" :aria-selected="chosen(item)" :aria-disabled="item.disabled || undefined" @pointermove="!item.disabled && (active = index)" @click="change(item)"><span>{{ item.label }}</span><UiIcon v-if="chosen(item)" name="check" /></div>
      <div v-if="!items.length" class="ui-option disabled">暂无选项</div>
    </div></Teleport>
  </span>
</template>
