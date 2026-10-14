// Compatibility exports: all geometry is from the supplied Sketch, not Element.
import { defineComponent, h } from 'vue'
import UiIcon from './UiIcon.vue'
function source(name) { return defineComponent({ name: `Sketch${name}`, setup: () => () => h(UiIcon, { name }) }) }
export const House = source('House'), Box = source('Box'), User = source('User'), Key = source('Key'), Document = source('Document')
export const Loading = source('Loading'), View = source('View'), Hide = source('Hide'), Lock = source('Lock'), Right = source('Right')
export const Tickets = source('Tickets'), Location = source('Location'), WarningFilled = source('WarningFilled'), Connection = source('Connection')
