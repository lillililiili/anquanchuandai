// Component 100, D1Y8tE-ndrB_DsfKhfE7C: 4px radius, rgba(0,0,0,.9), 4px 8px.
// Delegate so table cells and content created after API responses share the same tooltip.
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
    const a=node.getBoundingClientRect(), r=tip.getBoundingClientRect()
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
