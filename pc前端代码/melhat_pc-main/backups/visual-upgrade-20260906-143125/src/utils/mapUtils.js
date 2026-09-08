// map-utils.js
import { Feature } from "ol";
import { Stroke, Style, Circle as CircleStyle, Fill, Text } from "ol/style";
import { Vector as VectorLayer } from "ol/layer";
import VectorSource from "ol/source/Vector";
import { fromLonLat } from "ol/proj";
import { Point, LineString } from "ol/geom";

/** 清除地图上的所有标点和线路 */
export const clearMapOverlays = (map) => {
  if (!map) {
    return; // 确保map已经初始化
  }

  const layersToRemove = map
    .getLayers()
    .getArray()
    .filter((layer) => layer instanceof VectorLayer);

  layersToRemove.forEach((layer) => {
    map.removeLayer(layer);
  });
};

/** 添加单个标点 */
export const addMarker = (map, coord, index) => {
  const vectorSource = new VectorSource({});
  const pointLayer = new VectorLayer({
    source: vectorSource,
    style: function (feature, resolution) {
      const text = (index + 1).toString(); // 使用索引+1作为文本内容
      return new Style({
        image: new CircleStyle({
          radius: 7,
          fill: new Fill({ color: "red" }),
          stroke: new Stroke({
            color: "white",
            width: 2,
          }),
        }),
        text: new Text({
          text: text,
          fill: new Fill({ color: "white" }),
          offsetY: 20,
          textAlign: "center",
          backgroundFill: new Fill({ color: "rgba(0, 0, 0, 0.5)" }),
          padding: [3, 6, 3, 6],
        }),
      });
    },
    zIndex: 4,
    name: "marker",
  });

  map.addLayer(pointLayer);

  vectorSource.addFeature(
    new Feature({
      type: "point",
      geometry: new Point(fromLonLat(coord)),
    })
  );
};

/** 添加线路 */
export const addPolyline = (map, coords) => {
  const transformedCoords = coords.map((coord) => fromLonLat(coord));
  const lineString = new LineString(transformedCoords);

  const vectorSource = new VectorSource({
    features: [new Feature({ geometry: lineString })],
  });

  const lineLayer = new VectorLayer({
    source: vectorSource,
    style: new Style({
      stroke: new Stroke({
        color: "red",
        width: 2,
        lineDash: [5, 5],
      }),
    }),
    name: "line", // 设置图层名称，方便后续操作
  });

  map.addLayer(lineLayer);
};
