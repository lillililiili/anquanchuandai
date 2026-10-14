<script setup>
import { computed, ref, useAttrs, useId, nextTick, watch } from 'vue'
import UiIcon from './UiIcon.vue'
import { usePopup } from './usePopup'
import { useControlLabel } from './useControlLabel'
import { parseLocal, localString, monthDays, withinRange, pad } from './date-model'
defineOptions({ inheritAttrs: false })
const props = defineProps({ modelValue: { default: undefined }, value: { default: undefined }, type: { default: 'date' }, name: String, required: Boolean, disabled: Boolean, readonly: Boolean, min: String, max: String, step: [String,Number], placeholder: String })
const emit = defineEmits(['update:modelValue','input','change','blur','focus'])
const attrs = useAttrs(), uid = useId(), trigger = ref(null), native = ref(null), invalid = ref(false)
const controlLabel = useControlLabel(trigger)
const selected = computed(() => props.modelValue !== undefined ? props.modelValue : props.value || '')
const display = ref(selected.value)
watch(selected,value=>{display.value=value;invalid.value=false})
const isTime = computed(() => props.type === 'datetime-local'), seconds = computed(() => Number(props.step) < 60 || /:\d\d:\d\d$/.test(selected.value))
const now = new Date(), year = ref(now.getFullYear()), month = ref(now.getMonth()+1), day = ref(now.getDate()), hour = ref(0), minute = ref(0), second = ref(0), mode = ref('days'), focused = ref('')
const { open, panel, target, position, show, close, place } = usePopup(trigger, { width: () => isTime.value ? 504 : 312, boundary: () => trigger.value?.parentElement })
const days = computed(() => monthDays(year.value, month.value))
const years = computed(() => Array.from({length:12},(_,i)=>Math.floor(year.value/12)*12+i))
function valueFor(d) { return localString({...d,hour:hour.value,minute:minute.value,second:second.value}, isTime.value, seconds.value) }
function disabledDay(d) { const s=localString(d); return (props.min && s<props.min.slice(0,10)) || (props.max && s>props.max.slice(0,10)) }
async function commit(value) {
  if (value && (!parseLocal(value) || !withinRange(value,props.min,props.max))) { invalid.value=true; return }
  display.value=value; emit('update:modelValue', value); invalid.value = false
  await nextTick()
  if(native.value) { native.value.value=value; native.value.dispatchEvent(new Event('input',{bubbles:true})); native.value.dispatchEvent(new Event('change',{bubbles:true})) }
  close(true)
}
async function expand() {
  if (props.disabled || props.readonly) return
  const p=parseLocal(selected.value) || {year:now.getFullYear(),month:now.getMonth()+1,day:now.getDate(),hour:0,minute:0,second:0}
  year.value=p.year;month.value=p.month;day.value=p.day;hour.value=p.hour;minute.value=p.minute;second.value=p.second;mode.value='days';focused.value=localString(p)
  await show(); await nextTick(); panel.value?.querySelector('[tabindex="0"]')?.focus()
  panel.value?.querySelectorAll('.ui-time-column .selected').forEach(n => { n.parentElement.scrollTop=n.offsetTop-n.parentElement.offsetTop })
}
function choose(d) { if(disabledDay(d))return; year.value=d.year;month.value=d.month;day.value=d.day;focused.value=localString(d); if(!isTime.value) commit(valueFor(d)) }
function shift(delta) {
  if(mode.value==='years')year.value+=delta*12
  else if(mode.value==='months')year.value+=delta
  else { const d=new Date(year.value,month.value-1+delta,1);year.value=d.getFullYear();month.value=d.getMonth()+1;day.value=Math.min(day.value,new Date(year.value,month.value,0).getDate()) }
  focused.value=localString({year:year.value,month:month.value,day:day.value}); nextTick(place)
}
function keys(e,d) {
  const deltas={ArrowLeft:-1,ArrowRight:1,ArrowUp:-7,ArrowDown:7}
  if(e.key in deltas) { e.preventDefault();const n=new Date(d.year,d.month-1,d.day+deltas[e.key]);year.value=n.getFullYear();month.value=n.getMonth()+1;focused.value=localString({year:year.value,month:month.value,day:n.getDate()});nextTick(()=>panel.value?.querySelector(`[data-day="${focused.value}"]`)?.focus()) }
  else if(e.key==='PageUp'||e.key==='PageDown'){e.preventDefault();shift(e.key==='PageUp'?-1:1);nextTick(()=>panel.value?.querySelector(`[data-day="${focused.value}"]`)?.focus())}
}
function timeKey(e, value, count, field) {
  if(!['ArrowUp','ArrowDown','Home','End'].includes(e.key))return
  e.preventDefault();const n=e.key==='Home'?0:e.key==='End'?count-1:(value+(e.key==='ArrowDown'?1:-1)+count)%count
  if(field==='hour')hour.value=n;else if(field==='minute')minute.value=n;else second.value=n
  nextTick(()=>panel.value?.querySelector(`[data-time="${field}-${n}"]`)?.focus())
}
function typed(e) { const v=e.target.value; if(!v||parseLocal(v))commit(v);else invalid.value=true }
watch(()=>props.disabled,v=>{if(v)close()})
watch(invalid,v=>native.value?.setCustomValidity(v?'请输入有效日期':''))
watch(()=>[days.value.length,mode.value],()=>nextTick(place))
defineExpose({focus:()=>trigger.value?.focus()})
</script>
<template>
  <span class="ui-date" :class="[attrs.class,{'is-invalid':invalid,'is-disabled':disabled}]" :style="attrs.style">
    <input ref="native" class="ui-native-proxy" :type="type" :name="name" :value="selected" :required="required" :disabled="disabled" :min="min" :max="max" :step="step" tabindex="-1" aria-hidden="true" @focus="trigger?.focus()" @invalid.prevent="invalid=true;trigger?.focus()" @input="emit('input',$event)" @change="emit('change',$event)" />
    <input ref="trigger" class="ui-date-input" type="text" :id="attrs.id" :value="display" :disabled="disabled" :readonly="readonly" :placeholder="placeholder || (isTime ? 'YYYY-MM-DDTHH:mm' : 'YYYY-MM-DD')" :aria-label="attrs['aria-label'] || attrs.ariaLabel || controlLabel || undefined" :aria-describedby="attrs['aria-describedby']" :aria-invalid="invalid || attrs['aria-invalid']" :aria-required="required || undefined" aria-haspopup="dialog" :aria-expanded="open" :aria-controls="uid" @input="display=$event.target.value" @click="expand" @keydown.down.prevent="expand" @keydown.enter.prevent="typed" @change="typed" @blur="emit('blur',$event)" @focus="emit('focus',$event)" />
    <button v-if="selected && !disabled && !readonly" type="button" class="ui-date-clear" aria-label="清空日期" @click="commit('')"><UiIcon name="close" /></button>
    <button type="button" class="ui-date-open" :disabled="disabled || readonly" aria-label="打开日期选择器" @click="open ? close(true) : expand()"><UiIcon name="calendar" /></button>
    <Teleport :to="target"><section v-if="open" :id="uid" ref="panel" class="ui-popup ui-calendar" :class="{'with-time':isTime}" :style="position" role="dialog" aria-label="日期选择器">
      <div class="ui-calendar-board">
      <header class="ui-calendar-header"><button type="button" aria-label="上一年" @click="year--;place()"><UiIcon name="chevron-left-double" style="transform:rotate(-90deg)" /></button><button type="button" aria-label="上一页日期" @click="shift(-1)"><UiIcon name="chevron-left" /></button><span class="ui-calendar-caption"><button type="button" @click="mode=mode==='years'?'days':'years'">{{ year }}年</button><button type="button" @click="mode=mode==='months'?'days':'months'">{{ month }}月</button></span><button type="button" aria-label="下一页日期" @click="shift(1)"><UiIcon name="chevron-right" /></button><button type="button" aria-label="下一年" @click="year++;place()"><UiIcon name="chevron-right-double" style="transform:rotate(-90deg)" /></button></header>
      <div v-if="mode==='years'" class="ui-calendar-choices"><button v-for="y in years" type="button" :key="y" @click="year=y;mode='months'">{{ y }}</button></div>
      <div v-else-if="mode==='months'" class="ui-calendar-choices"><button v-for="m in 12" type="button" :key="m" @click="month=m;mode='days'">{{ m }}月</button></div>
      <template v-else><div class="ui-weekdays"><span v-for="w in ['日','一','二','三','四','五','六']" :key="w">{{ w }}</span></div><div class="ui-days" role="grid" aria-label="日期">
        <button v-for="d in days" :key="localString(d)" :data-day="localString(d)" type="button" role="gridcell" :aria-label="localString(d)" :aria-selected="localString(d)===String(selected).slice(0,10)" :disabled="disabledDay(d)" :tabindex="localString(d)===focused?0:-1" :class="{outside:d.month!==month,selected:localString(d)===String(selected).slice(0,10),today:localString(d)===localString({year:now.getFullYear(),month:now.getMonth()+1,day:now.getDate()}),draft:isTime&&d.year===year&&d.month===month&&d.day===day}" @click="choose(d)" @keydown="keys($event,d)">{{ d.day }}</button>
      </div></template>
      </div>
      <aside v-if="isTime" class="ui-calendar-time"><div class="ui-time-caption">{{ pad(hour) }}:{{ pad(minute) }}<template v-if="seconds">:{{ pad(second) }}</template></div><div class="ui-time-columns">
        <div class="ui-time-column" role="listbox" aria-label="小时"><button v-for="i in 24" :key="i" :data-time="`hour-${i-1}`" type="button" role="option" :aria-selected="hour===i-1" :class="{selected:hour===i-1}" :tabindex="hour===i-1?0:-1" @click="hour=i-1" @keydown="timeKey($event,i-1,24,'hour')">{{ pad(i-1) }}</button></div>
        <div class="ui-time-column" role="listbox" aria-label="分钟"><button v-for="i in 60" :key="i" :data-time="`minute-${i-1}`" type="button" role="option" :aria-selected="minute===i-1" :class="{selected:minute===i-1}" :tabindex="minute===i-1?0:-1" @click="minute=i-1" @keydown="timeKey($event,i-1,60,'minute')">{{ pad(i-1) }}</button></div>
        <div v-if="seconds" class="ui-time-column" role="listbox" aria-label="秒"><button v-for="i in 60" :key="i" :data-time="`second-${i-1}`" type="button" role="option" :aria-selected="second===i-1" :class="{selected:second===i-1}" :tabindex="second===i-1?0:-1" @click="second=i-1" @keydown="timeKey($event,i-1,60,'second')">{{ pad(i-1) }}</button></div>
      </div></aside>
      <footer v-if="isTime" class="ui-calendar-footer"><button type="button" class="ui-link" @click="commit('')">清空</button><button type="button" class="ui-link" @click="choose({year:now.getFullYear(),month:now.getMonth()+1,day:now.getDate()})">今天</button><button type="button" class="ui-primary" :disabled="!withinRange(valueFor({year,month,day}),min,max)" @click="commit(valueFor({year,month,day}))">确定</button></footer>
    </section></Teleport>
  </span>
</template>
