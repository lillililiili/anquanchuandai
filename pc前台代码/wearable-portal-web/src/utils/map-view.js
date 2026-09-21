import { buffer, createEmpty, extend, getWidth, getHeight, isEmpty } from 'ol/extent.js'

export const MAP_FIT_PADDING = [90, 65, 65, 65]
export const MAP_POINT_BUFFER = 48
export const MAP_MAX_FIT_ZOOM = 16
export const MAP_FOCUS_ZOOM = 18

export function overlayFitPadding(detailOpen, width = 0) {
  if (!detailOpen) return MAP_FIT_PADDING
  const left = width >= 520 ? 380 : Math.max(48, Math.round((width || 360) * 0.38))
  return [110, 72, 80, left]
}

export function viewFitsSize(size, padding) {
  return !!size && size[0] > padding[1] + padding[3] + 24 && size[1] > padding[0] + padding[2] + 24
}

export function mergeExtents(sources) {
  const extent = createEmpty()
  let any = false
  for (const source of sources) {
    if (!source?.getFeatures()?.length) continue
    extend(extent, source.getExtent())
    any = true
  }
  return any && !isEmpty(extent) ? extent : null
}

export function prepareFitExtent(extent) {
  if (!extent) return null
  if (getWidth(extent) < 1 || getHeight(extent) < 1) return buffer(extent, MAP_POINT_BUFFER)
  return extent
}

export function offsetCenter(coord, size, padding, resolution) {
  const cx = padding[3] + (size[0] - padding[1] - padding[3]) / 2
  const cy = padding[0] + (size[1] - padding[0] - padding[2]) / 2
  return [coord[0] - (cx - size[0] / 2) * resolution, coord[1] - (size[1] / 2 - cy) * resolution]
}
