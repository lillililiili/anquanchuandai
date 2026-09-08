import {
    centerPoint,
    maxZoom,
    minZoom,
    overlayTilesUrl,
    satelliteTilesUrl,
    zoom
  } from '@/common.config'
  import { Map, View } from 'ol'
  import TileLayer from 'ol/layer/Tile'
  import { fromLonLat } from 'ol/proj'
  import { XYZ } from 'ol/source'
  
  export function useMap(map) {
    const mapView = reactive({
      center: fromLonLat(centerPoint),
      zoom,
      minZoom,
      maxZoom
    })
  
    const satelliteLayer = new TileLayer({
      source: new XYZ({
        url: satelliteTilesUrl
      })
    })
    const overlayLayer = new TileLayer({
      source: new XYZ({
        url: overlayTilesUrl
      })
    })
  
    map = new Map({
      layers: [satelliteLayer, overlayLayer],
      view: new View(mapView),
      target: 'map'
    })
  
    return { map }
}