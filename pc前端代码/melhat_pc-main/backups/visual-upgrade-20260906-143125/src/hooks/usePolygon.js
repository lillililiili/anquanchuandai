import { ref } from 'vue';
import Feature from 'ol/Feature';
import Polygon from 'ol/geom/Polygon';
import { Draw, Modify } from 'ol/interaction';
import { Vector as VectorLayer } from 'ol/layer';
import { Vector as VectorSource } from 'ol/source';
import { Circle as CircleStyle, Fill, Stroke, Style } from 'ol/style';
import { fromLonLat, toLonLat } from 'ol/proj';

let drawInstances = [];
let sharedAreaSource = null; // 共享的矢量数据源，避免多次调用时替换图层导致功能丢失

// 共享默认样式，避免每次调用重新创建
const defaultAreaStyle = new Style({
  fill: new Fill({
    color: 'rgba(255,0,0,0.3)',
  }),
  stroke: new Stroke({
    color: 'rgba(255,0,0,0.8)',
    width: 2,
  }),
  image: new CircleStyle({
    radius: 5,
    fill: new Fill({
      color: 'rgba(255,0,0,0.4)',
    }),
  }),
});

export function usePolygon(map, areaCoordinates = null, areaStyle = null) {
  let areaLayer = null;
  let draw = ref(null);
  let coordinates = ref(null);
  let modifyHandler = null;
  let drawHandler = null;

  const areaStyleToUse = areaStyle || defaultAreaStyle;

  // 复用共享数据源，避免多次调用时替换图层导致功能丢失
  if (!sharedAreaSource) {
    sharedAreaSource = new VectorSource({ wrapX: false });
  }

  // 遍历地图上的所有图层，找到名称为 'areaLayer' 的图层，并设置其源（source）和样式（style）
  map.getLayers().forEach((layer) => {
    if (layer.get('name') === 'areaLayer') {
      areaLayer = layer;
      areaLayer.setSource(sharedAreaSource);
      areaLayer.setStyle(areaStyleToUse);
      // 确保围栏图层在瓦片图层之上
      if (!areaLayer.getZIndex() || areaLayer.getZIndex() < 100) {
        areaLayer.setZIndex(100);
      }
    }
  });

  // 如果没有图层，则添加一个
  if (!areaLayer) {
    areaLayer = new VectorLayer({
      source: sharedAreaSource,
      style: areaStyleToUse,
      name: 'areaLayer',
      zIndex: 100,
    });
    map.addLayer(areaLayer);
  }

  // 创建modify交互
  const modify = new Modify({ source: sharedAreaSource });

  // 交互发生变化，触发 modifyend 事件
  const onCoordinatesUpdated = (callback) => {
    modifyHandler = (e) => {
      const mercatorCoords = e.features
        .getArray()[0]
        .getGeometry()
        .getCoordinates()[0];

      coordinates.value = mercatorCoords.map((coord) => {
        const lonLat = toLonLat(coord);
        return [Number(lonLat[0].toFixed(6)), Number(lonLat[1].toFixed(6))];
      });

      callback(coordinates.value);
    };
    modify.on('modifyend', modifyHandler);
  };

  map.addInteraction(modify);

  // 清理函数 - 移除事件监听器和交互
  const cleanup = () => {
    if (modifyHandler) {
      modify.un('modifyend', modifyHandler);
      modifyHandler = null;
    }
    if (drawHandler && draw.value) {
      draw.value.un('drawend', drawHandler);
      drawHandler = null;
    }
    map.removeInteraction(modify);
    if (draw.value) {
      map.removeInteraction(draw.value);
    }
  };

  // areaCoordinates有值，根据坐标绘制，没有开启手动绘制
  if (areaCoordinates) {
    cleanup();
    draw.value = null;
    // 先清空共享数据源，再绘制
    sharedAreaSource.clear();

    // 将经纬度转换为 Mercator 坐标用于绘制
    const mercatorCoords = areaCoordinates[0].map((coordinate) => {
      const lng = parseFloat(coordinate[0]);
      const lat = parseFloat(coordinate[1]);
      return fromLonLat([lng, lat]);
    });

    const areaFeature = new Feature({
      geometry: new Polygon([mercatorCoords]),
    });
    sharedAreaSource.addFeature(areaFeature);
  } else {
    if (draw.value !== null) {
      map.removeInteraction(draw.value);
    }
    // 先清空共享数据源
    sharedAreaSource.clear();
    draw.value = new Draw({
      source: sharedAreaSource,
      type: 'Polygon',
      style: defaultAreaStyle,
    });

    map.addInteraction(draw.value);
  }

  // 启用或禁用绘制功能
  const toggleDrawing = (enable) => {
    if (enable) {
      if (!draw.value) {
        draw.value = new Draw({
          source: sharedAreaSource,
          type: 'Polygon',
          style: defaultAreaStyle,
        });
        map.addInteraction(draw.value);
        drawInstances.push(draw.value);
      }
    } else {
      if (draw.value) {
        const instanceToRemove = draw.value;
        map.removeInteraction(instanceToRemove);
        drawInstances = drawInstances.filter(
          (instance) => instance !== instanceToRemove
        );
        draw.value = null;
      }
    }
  };

  // 绘制区域
  const drawArea = () => {
    return new Promise((resolve) => {
      toggleDrawing(true);

      if (draw.value) {
        // 移除之前的监听器，防止重复绑定
        if (drawHandler) {
          draw.value.un('drawend', drawHandler);
        }

        drawHandler = (e) => {
          const mercatorCoords = e.feature.getGeometry().getCoordinates()[0];

          const polygonCoordinates = mercatorCoords.map((coord) => {
            const lonLat = toLonLat(coord);
            return [Number(lonLat[0].toFixed(6)), Number(lonLat[1].toFixed(6))];
          });

          toggleDrawing(false);
          coordinates.value = polygonCoordinates;
          drawHandler = null;

          resolve(polygonCoordinates);
        };

        draw.value.on('drawend', drawHandler);
      }
    });
  };

  return { drawArea, toggleDrawing, onCoordinatesUpdated, cleanup };
}

// 删除所有绘制交互
export function removeAllDrawInstances() {
  for (let draw of drawInstances) {
    const map = draw.getMap();
    if (map) {
      map.removeInteraction(draw);
    }
  }
  drawInstances = [];
}