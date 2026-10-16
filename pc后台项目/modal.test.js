import { afterEach, describe, expect, it, vi } from 'vitest'
import { dialogSize, restoreDialogFocus, shouldCloseDialog } from '../shared/ui-spec/dialog'
import { closeModal, modal, openModal } from '../pc前台项目/src/stores/modal'

afterEach(() => { closeModal(); vi.unstubAllGlobals() })

describe('shared dialog interaction contract', () => {
  it('lets a calendar or select consume Escape without closing its parent', () => {
    expect(shouldCloseDialog({ key: 'Escape', defaultPrevented: true })).toBe(false)
    expect(shouldCloseDialog({ key: 'Escape', defaultPrevented: false })).toBe(true)
    expect(shouldCloseDialog({ key: 'Tab', defaultPrevented: false })).toBe(false)
  })
  it('does not focus controls removed by navigation or disabled while saving', () => {
    const focus = vi.fn()
    restoreDialogFocus({ isConnected: false, focus })
    restoreDialogFocus({ isConnected: true, disabled: true, focus })
    expect(focus).not.toHaveBeenCalled()
    restoreDialogFocus({ isConnected: true, focus })
    expect(focus).toHaveBeenCalledWith({ preventScroll: true })
  })
  it('keeps the page trigger when a record dialog replaces its list dialog', () => {
    const trigger = { isConnected: true, focus: vi.fn() }
    const inside = { isConnected: true, focus: vi.fn() }
    vi.stubGlobal('document', { activeElement: trigger })
    openModal({ title: '记录列表', wide: true })
    document.activeElement = inside
    openModal({ title: '记录详情', size: 'compact', layout: 'form' })
    closeModal()
    expect(trigger.focus).toHaveBeenCalledOnce()
    expect(inside.focus).not.toHaveBeenCalled()
  })
  it('resets layout between openings and preserves legacy wide callers', () => {
    vi.stubGlobal('document', { activeElement: null })
    openModal({ title: '编辑', layout: 'form', size: 'compact' })
    closeModal()
    openModal({ title: '记录', wide: true })
    expect(modal.layout).toBe('content')
    expect(dialogSize(modal.size, modal.wide)).toBe('wide')
    expect(dialogSize('compact', true)).toBe('compact')
  })
})
