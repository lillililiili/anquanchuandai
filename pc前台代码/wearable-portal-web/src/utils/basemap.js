import TileLayer from 'ol/layer/Tile.js'
import XYZ from 'ol/source/XYZ.js'

/** 与 pc前端代码/melhat_pc-main 备份分支同一套 XYZ 底图。 */
export const OSM_TILES = 'https://{a-c}.tile.openstreetmap.org/{z}/{x}/{y}.png'
export const SATELLITE_TILES = 'https://webst01.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}'
export const OVERLAY_TILES = 'https://webst01.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}'
export const MAP_CENTER = [117.14473200, 36.66388700]
export const MAP_ZOOM = 15
export const MAP_MIN_ZOOM = 3
export const MAP_MAX_ZOOM = 18

export function createBasemapLayers() {
  return {
    street: new TileLayer({ source: new XYZ({ url: OSM_TILES }), zIndex: 0 }),
    satellite: new TileLayer({ source: new XYZ({ url: SATELLITE_TILES }), zIndex: 1, visible: false }),
    overlay: new TileLayer({ source: new XYZ({ url: OVERLAY_TILES }), zIndex: 2, visible: false })
  }
}
