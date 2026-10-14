import { ref, onMounted, onUpdated } from 'vue'
export function useControlLabel(control) {
  const label=ref('')
  function update(){
    const wrapper=control.value?.closest('label')
    if(!wrapper)return
    const text=[...wrapper.childNodes].filter(n=>!n.contains?.(control.value)&&n.nodeName!=='SMALL').map(n=>n.textContent).join(' ').trim()
    if(label.value!==text)label.value=text
  }
  onMounted(update);onUpdated(update)
  return label
}
