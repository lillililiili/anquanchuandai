import icons from './icons.json'
import aliases from './icon-aliases.json'
let instance = 0

export function resolveIcon(name) {
  return aliases[name] || (icons[name] ? name : '')
}
export function iconMarkup(name, className = '') {
  const key = resolveIcon(name), icon = icons[key]
  if (!icon) {
    if (import.meta.env?.DEV) console.warn(`Unmapped Sketch icon: ${name}`)
    return ''
  }
  const body=icon.body.replaceAll('clip-', `dynamic-${++instance}-clip-`)
  return `<svg class="ui-icon ${className}" data-source-icon="${key}" viewBox="${icon.viewBox}" aria-hidden="true" focusable="false">${body}</svg>`
}
export { icons, aliases }
