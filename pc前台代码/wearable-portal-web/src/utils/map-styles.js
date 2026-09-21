import { Style, Circle, Fill, Stroke } from 'ol/style.js'

const ink = '#061428'
const cyan = '#00e8ff'
const gold = '#ffb020'

function dots(radius, fill, stroke, width) {
  return new Style({ image: new Circle({ radius, fill: new Fill({ color: fill }), stroke: stroke ? new Stroke({ color: stroke, width }) : undefined }) })
}

export function locationStyles() {
  return [
    dots(18, 'rgba(0,232,255,.32)'),
    dots(10, cyan, '#ffffff', 4),
    dots(10, 'rgba(0,0,0,0)', ink, 1.5)
  ]
}

export function samplePointStyles() {
  return [
    dots(9, cyan, '#ffffff', 3),
    dots(9, 'rgba(0,0,0,0)', ink, 1.25)
  ]
}

export function trajectoryLineStyles() {
  return [
    new Style({ stroke: new Stroke({ color: ink, width: 12, lineCap: 'round', lineJoin: 'round' }) }),
    new Style({ stroke: new Stroke({ color: '#ffffff', width: 8, lineCap: 'round', lineJoin: 'round' }) }),
    new Style({ stroke: new Stroke({ color: cyan, width: 5, lineCap: 'round', lineJoin: 'round' }) })
  ]
}

export function emphasisStyles() {
  return [
    dots(20, 'rgba(255,176,32,.38)'),
    dots(12, gold, '#ffffff', 4),
    dots(12, 'rgba(0,0,0,0)', ink, 1.5)
  ]
}

export function fenceStyles() {
  return new Style({ stroke: new Stroke({ color: cyan, width: 3 }), fill: new Fill({ color: 'rgba(0,232,255,.12)' }) })
}

export function selectedFenceStyles() {
  return new Style({ stroke: new Stroke({ color: gold, width: 4 }), fill: new Fill({ color: 'rgba(255,176,32,.22)' }) })
}

export function overlayStyle(trajectory) {
  return feature => {
    const type = feature.getGeometry()?.getType()
    if (type === 'LineString') return trajectoryLineStyles()
    if (type === 'Point') return trajectory ? samplePointStyles() : locationStyles()
    return fenceStyles()
  }
}
