import { defineStore } from 'pinia'
import { Map, View } from 'ol'
import TileLayer from 'ol/layer/Tile'
import { XYZ } from 'ol/source'
import { fromLonLat } from 'ol/proj'
import { Vector as VectorLayer } from 'ol/layer'
import { Vector as SourceVec } from 'ol/source'
import { defaults as defaultControls } from 'ol/control'
import {
  centerPoint,
  maxZoom,
  minZoom,
  overlayTilesUrl,
  satelliteTilesUrl,
  zoom
} from '@/common.config'

const useMapStore = defineStore('map', {
  state: () => ({
    map: null,
    isInitialized: false,
    vectorSource: null,
    pointLayer: null,
    trackSource: null,
    trackLayer: null,
    currentTarget: null
  }),

  actions: {
    // 初始化或复用地图实例
    initMap(target) {
      // 如果已初始化且 target 相同，直接返回
      if (this.isInitialized && this.currentTarget === target) {
        return this.map
      }

      // 如果已初始化但 target 不同，只更新 target
      if (this.isInitialized && this.map) {
        this.map.setTarget(target)
        this.currentTarget = target
        // 关键：切换 target 后必须更新尺寸，否则地图不会渲染
        this.map.updateSize()
        return this.map
      }

      // 首次初始化
      this.map = new Map({
        target: target || 'map',
        layers: [
          new TileLayer({
            source: new XYZ({
              url: 'https://{a-c}.tile.openstreetmap.org/{z}/{x}/{y}.png'
            }),
            zIndex: 0
          }),
          new TileLayer({
            source: new XYZ({
              url: satelliteTilesUrl
            }),
            zIndex: 1
          }),
          new TileLayer({
            source: new XYZ({
              url: overlayTilesUrl
            }),
            zIndex: 2
          })
        ],
        view: new View({
          center: fromLonLat(centerPoint),
          zoom,
          minZoom,
          maxZoom
        }),
        controls: defaultControls({
          zoom: true,
          rotate: false,
          attribution: false
        })
      })

      // 初始化矢量图层
      this.vectorSource = new SourceVec()
      this.pointLayer = new VectorLayer({
        source: this.vectorSource,
        zIndex: 4
      })
      this.map.addLayer(this.pointLayer)

      // 初始化轨迹图层
      this.trackSource = new SourceVec()
      this.trackLayer = new VectorLayer({
        source: this.trackSource,
        zIndex: 3
      })
      this.map.addLayer(this.trackLayer)

      this.isInitialized = true
      this.currentTarget = target

      return this.map
    },

    // 清除业务图层（不销毁地图实例）
    clearBusinessLayers() {
      this.clearTrack()
      this.clearMarkers()
      this.clearLines()
      this.clearPolygons()
    },

    clearMarkers() {
      if (this.vectorSource) {
        const features = this.vectorSource.getFeatures()
        features.forEach(f => {
          if (f.getGeometry()?.getType() === 'Point') {
            this.vectorSource.removeFeature(f)
          }
        })
      }
    },

    clearLines() {
      if (this.vectorSource) {
        const features = this.vectorSource.getFeatures()
        features.forEach(f => {
          if (f.getGeometry()?.getType() === 'LineString') {
            this.vectorSource.removeFeature(f)
          }
        })
      }
    },

    clearPolygons() {
      if (this.vectorSource) {
        const features = this.vectorSource.getFeatures()
        features.forEach(f => {
          if (f.getGeometry()?.getType() === 'Polygon') {
            this.vectorSource.removeFeature(f)
          }
        })
      }
    },

    clearTrack() {
      if (this.trackSource) {
        this.trackSource.clear()
      }
    },

    // 页面离开时调用，清除业务图层
    resetForNewPage() {
      this.clearBusinessLayers()
      // 不销毁地图，只清除图层内容
    },

    // 完全销毁地图（仅在应用退出时调用）
    destroyMap() {
      this.clearBusinessLayers()
      if (this.map) {
        this.map.setTarget(undefined)
        this.map = null
      }
      this.vectorSource = null
      this.pointLayer = null
      this.trackSource = null
      this.trackLayer = null
      this.isInitialized = false
      this.currentTarget = null
    }
  }
})

export default useMapStore