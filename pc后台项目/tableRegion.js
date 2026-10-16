const regions = new WeakMap()
export function resultRegionHeight(viewportHeight, top, footer = 28) {
  return Math.max(180, Math.floor(viewportHeight - top - footer))
}
export const tableRegion = {
  mounted(element) {
    let frame
    const measure = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => {
        const top = element.getBoundingClientRect().top + window.scrollY
        const main = element.closest('main'), footer = main?.querySelector(':scope > .workspace-footer')
        const pixels = value => Number.parseFloat(value) || 0
        let reserve = 0
        // Include the enclosing card and page padding, plus the footer outside the
        // result area. Measuring these avoids an extra page scrollbar at short heights.
        for (let parent = element.parentElement; parent; parent = parent.parentElement) {
          const style = getComputedStyle(parent)
          reserve += pixels(style.paddingBottom) + pixels(style.borderBottomWidth) + pixels(style.marginBottom)
          if (parent === main) break
        }
        if (footer) { const style = getComputedStyle(footer); reserve += footer.offsetHeight + pixels(style.marginTop) + pixels(style.marginBottom) }
        element.style.setProperty('--admin-results-height', `${resultRegionHeight(window.innerHeight, top, reserve)}px`)
      })
    }
    const observer = new ResizeObserver(measure)
    observer.observe(element.parentElement)
    const main = element.closest('main')
    if (main) for (const child of main.children) observer.observe(child)
    // Filter rows and notices above a result region can change its available height.
    for (const sibling of element.parentElement.children) if (sibling !== element) observer.observe(sibling)
    window.addEventListener('resize', measure)
    regions.set(element, () => { cancelAnimationFrame(frame); observer.disconnect(); window.removeEventListener('resize', measure) })
    measure()
  },
  unmounted(element) { regions.get(element)?.(); regions.delete(element) },
}
