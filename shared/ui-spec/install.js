import UiSelect from './UiSelect.vue'
import UiDatePicker from './UiDatePicker.vue'
import UiIcon from './UiIcon.vue'
import UiSwitch from './UiSwitch.vue'
import { installTooltips } from './tooltip'
export function installUiSpec(app) {
  app.component('UiSelect',UiSelect).component('UiDatePicker',UiDatePicker).component('UiIcon',UiIcon).component('UiSwitch',UiSwitch)
  document.documentElement.classList.add('ui-spec-loaded')
  app.onUnmount(installTooltips())
}
