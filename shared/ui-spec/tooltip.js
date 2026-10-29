// Component 100, D1Y8tE-ndrB_DsfKhfE7C: 4px radius, rgba(0,0,0,.9), 4px 8px.
// Delegate so table cells and content created after API responses share the same tooltip.
function tooltipAnchor(node) {
  const bounds = node.getBoundingClientRect()
  if (!node.matches('.admin-table td, .admin-table th')) return bounds

  // Measure text rather than cell/block boxes, without changing Vue's DOM.
  const range = document.createRange()
  const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT)
  const rects = []
  for (let text = walker.nextNode(); text; text = walker.nextNode()) {
    if (!text.textContent.trim()) continue
    range.selectNodeContents(text)
    rects.push(...Array.from(range.getClientRects()).filter(rect => rect.width && rect.height))
  }
  if (!rects.length) return bounds
  const content = {
    left: Math.min(...rects.map(rect => rect.left)),
    right: Math.max(...rects.map(rect => rect.right)),
    top: Math.min(...rects.map(rect => rect.top)),
    bottom: Math.max(...rects.map(rect => rect.bottom)),
  }
  const style = getComputedStyle(node)
  // A Range includes text hidden by ellipsis; anchor to the visible portion.
  const left = Math.max(content.left, bounds.left + parseFloat(style.borderLeftWidth) + parseFloat(style.paddingLeft))
  const right = Math.min(content.right, bounds.right - parseFloat(style.borderRightWidth) - parseFloat(style.paddingRight))
  const top = Math.max(content.top, bounds.top)
  const bottom = Math.min(content.bottom, bounds.bottom)
  if (right <= left || bottom <= top) return bounds
  return { left, right, top, bottom, width: right - left, height: bottom - top }
}

export function installTooltips() {
  let owner, tip, oldTitle, oldDescription
  function hide() {
    if (owner) {
      if (!owner.hasAttribute('title')) owner.setAttribute('title', oldTitle)
      if (oldDescription) owner.setAttribute('aria-describedby', oldDescription)
      else owner.removeAttribute('aria-describedby')
    }
    tip?.remove(); owner = tip = null
  }
  function show(event) {
    const node = event.target.closest?.('[title]')
    if (!node || !node.title || node === owner) return
    hide(); owner = node; oldTitle = node.title; oldDescription = node.getAttribute('aria-describedby')
    node.removeAttribute('title')
    tip = document.createElement('div'); tip.id = 'ui-spec-tooltip'; tip.className = 'ui-tooltip'; tip.role = 'tooltip'; tip.textContent = oldTitle
    node.setAttribute('aria-describedby', [oldDescription, tip.id].filter(Boolean).join(' '))
    ;(node.closest('dialog, [role="dialog"]') || document.body).append(tip)
    const a=tooltipAnchor(node), r=tip.getBoundingClientRect()
    tip.style.left=`${Math.max(8,Math.min(a.left+(a.width-r.width)/2,innerWidth-r.width-8))}px`
    tip.style.top=`${a.top-r.height-6>=8?a.top-r.height-6:Math.min(a.bottom+6,innerHeight-r.height-8)}px`
  }
  function leave(e) { if (owner && !owner.contains(e.relatedTarget)) hide() }
  document.addEventListener('pointerover', show)
  document.addEventListener('focusin', show)
  document.addEventListener('pointerout', leave)
  document.addEventListener('focusout', leave)
  document.addEventListener('keydown', hide)
  document.addEventListener('pointerdown', hide)
  window.addEventListener('scroll', hide, true)
  window.addEventListener('resize', hide)
  return () => {
    hide()
    document.removeEventListener('pointerover',show); document.removeEventListener('focusin',show)
    document.removeEventListener('pointerout',leave); document.removeEventListener('focusout',leave)
    document.removeEventListener('keydown',hide); document.removeEventListener('pointerdown',hide)
    window.removeEventListener('scroll',hide,true); window.removeEventListener('resize',hide)
  }
}
