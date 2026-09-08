// useUnifiedMap.js
import { ref } from "vue";
import { fromLonLat } from "ol/proj";
import { Vector as VectorLayer } from "ol/layer";
import { Vector as SourceVec } from "ol/source";
import { Icon, Style, Stroke, Fill } from "ol/style";
import { Feature } from "ol";
import { Point, LineString, Polygon } from "ol/geom";
import MarkIcon from "@/assets/images/location.png";


import useMapStore from "@/store/modules/map";

export function useMap() {
  const mapStore = useMapStore();

  // 使用全局 store 的地图实例
  const map = ref(null);
  const isInitialized = ref(false);
  const vectorSource = ref(null);
  const pointLayer = ref(null);

  const MarkIconWidth = 30; // marker宽度
  const MarkIconHeight = 30; // marker高度
  const lineColor = "#FF0000"; // 线条颜色
  const PolygonFillColor = "rgba(255, 0, 0, 0.2)"; // 多边形填充颜色
  const lineWidth = 3; // 线条宽度

  // 轨迹回放相关状态（页面私有）
  const trackSource = ref(null);
  const trackLayer = ref(null);
  const trackMarker = ref(null);
  const trackLine = ref(null);
  const isPlaying = ref(false);
  const currentIndex = ref(0);
  const trackPoints = ref([]);
  const animationFrameId = ref(null);
  const segmentDuration = ref(1000);
  const animationStartTime = ref(0);
  const currentSegmentStartPoint = ref(null);
  const currentSegmentEndPoint = ref(null);
  const resolvePlaybackPromise = ref(null);
  const isPaused = ref(false);
  const pauseTime = ref(0);
  const pausePosition = ref(0);
  const currentSegmentProgress = ref(0);

  const createTrackMarkerStyle = () =>
    new Style({
      image: new Icon({
        src: MarkIcon,
        width: MarkIconWidth,
        height: MarkIconHeight,
        anchor: [0.5, 1],
        anchorXUnits: "fraction",
        anchorYUnits: "fraction",
      }),
    });

  const initMap = (target) => {
    // 使用全局 store 初始化地图（单例复用）
    const globalMap = mapStore.initMap(target);
    map.value = globalMap;
    vectorSource.value = mapStore.vectorSource;
    pointLayer.value = mapStore.pointLayer;
    trackSource.value = mapStore.trackSource;
    trackLayer.value = mapStore.trackLayer;
    isInitialized.value = true;
  };

  const addMarker = (coordinate, customStyle = {}) => {
    if (!isInitialized.value || !map.value) {
      console.error("Map is not initialized");
      return null;
    }

    const iconStyle = new Style({
      image: new Icon({
        ...customStyle,
        src: customStyle.src || MarkIcon,
        opacity: customStyle.opacity ?? 1,
        width: customStyle.width ?? MarkIconWidth,
        height: customStyle.height ?? MarkIconHeight,
        anchor: customStyle.anchor || [0.5, 1],
        anchorXUnits: customStyle.anchorXUnits || "fraction",
        anchorYUnits: customStyle.anchorYUnits || "fraction",
      }),
    });

    const feature = new Feature({
      type: "point",
      geometry: new Point(fromLonLat(coordinate)),
    });
    feature.setStyle(iconStyle);
    vectorSource.value.addFeature(feature);

    // 聚焦到新添加的标记
    map.value.getView().setCenter(fromLonLat(coordinate));

    return {
      remove: () => vectorSource.value.removeFeature(feature),
      setPosition: (newCoord) => {
        feature.getGeometry().setCoordinates(fromLonLat(newCoord));
      },
      getPosition: () => feature.getGeometry().getCoordinates(),
    };
  };

  const clearMarkers = () => {
    if (vectorSource.value) {
      const featuresToRemove = vectorSource.value
        .getFeatures()
        .filter((feature) => feature.getGeometry() instanceof Point);
      featuresToRemove.forEach((feature) =>
        vectorSource.value.removeFeature(feature)
      );
    }
  };

  const drawLine = (coordinates, customStyle = {}) => {
    if (!isInitialized.value || !map.value) {
      console.error("Map is not initialized");
      return null;
    }

    const lineStyle = new Style({
      stroke: new Stroke({
        color: customStyle.color || lineColor,
        width: customStyle.width || lineWidth,
      }),
    });

    const lineFeature = new Feature({
      type: "line",
      geometry: new LineString(coordinates.map((point) => fromLonLat(point))),
    });
    lineFeature.setStyle(lineStyle);
    vectorSource.value.addFeature(lineFeature);

    return {
      remove: () => vectorSource.value.removeFeature(lineFeature),
    };
  };

  const clearLines = () => {
    if (vectorSource.value) {
      const featuresToRemove = vectorSource.value
        .getFeatures()
        .filter((feature) => feature.getGeometry() instanceof LineString);
      featuresToRemove.forEach((feature) =>
        vectorSource.value.removeFeature(feature)
      );
    }
  };

  const drawPolygon = (coordinates, customStyle = {}) => {
    if (!isInitialized.value || !map.value) {
      console.error("Map is not initialized");
      return null;
    }

    const polygonStyle = new Style({
      stroke: new Stroke({
        color: customStyle.strokeColor || lineColor,
        width: customStyle.strokeWidth || lineWidth,
      }),
      fill: new Fill({
        color: customStyle.fillColor || PolygonFillColor,
      }),
    });

    const polygonFeature = new Feature({
      type: "polygon",
      geometry: new Polygon([coordinates.map((point) => fromLonLat(point))]),
    });
    polygonFeature.setStyle(polygonStyle);
    vectorSource.value.addFeature(polygonFeature);

    return {
      remove: () => vectorSource.value.removeFeature(polygonFeature),
    };
  };

  const clearPolygons = () => {
    if (vectorSource.value) {
      const featuresToRemove = vectorSource.value
        .getFeatures()
        .filter((feature) => feature.getGeometry() instanceof Polygon);
      featuresToRemove.forEach((feature) =>
        vectorSource.value.removeFeature(feature)
      );
    }
  };

  const clearAllBusinessLayers = () => {
    clearTrack();
    clearMarkers();
    clearLines();
    clearPolygons();
  };

  // 轨迹回放相关函数
  const playTrack = (points) => {
    if (!isInitialized.value || !map.value) {
      console.error("Map is not initialized");
      return Promise.reject("Map is not initialized");
    }

    return new Promise((resolve) => {
      stopTrack();
      resolvePlaybackPromise.value = resolve;

      // 清除之前的轨迹
      if (trackSource.value) {
        trackSource.value.clear();
      }

      // 设置新的轨迹点
      trackPoints.value = points;
      currentIndex.value = 0;
      isPlaying.value = true;

      if (!trackSource.value) {
        trackSource.value = new SourceVec();
        trackLayer.value = new VectorLayer({
          source: trackSource.value,
        });
        map.value.addLayer(trackLayer.value);
      }

      if (trackPoints.value.length === 0) {
        stopTrack();
        return;
      }

      const startCoord = fromLonLat(points[0]);

      // 只有一个点时，显示标记后停止
      if (trackPoints.value.length === 1) {
        trackMarker.value = new Feature({
          geometry: new Point(startCoord),
        });
        trackMarker.value.setStyle(createTrackMarkerStyle());
        trackSource.value.addFeature(trackMarker.value);
        map.value.getView().setCenter(startCoord);
        stopTrack();
        return;
      }

      // 用全部点计算 extent 用于 view.fit，但不画完整轨迹线
      const allMercatorCoords = points.map((p) => fromLonLat(p));
      const tempLine = new LineString(allMercatorCoords);
      const extent = tempLine.getExtent();

      // 创建"进度轨迹线"，初始只包含起点（单点不可见）
      trackLine.value = new Feature({
        geometry: new LineString([startCoord]),
      });
      trackLine.value.setStyle(
        new Style({
          stroke: new Stroke({
            color: lineColor,
            width: lineWidth,
          }),
        })
      );
      trackSource.value.addFeature(trackLine.value);

      // 创建 marker 在起点
      trackMarker.value = new Feature({
        geometry: new Point(startCoord),
      });
      trackMarker.value.setStyle(createTrackMarkerStyle());
      trackSource.value.addFeature(trackMarker.value);

      // 设置第一个轨迹段
      currentSegmentStartPoint.value = trackPoints.value[0];
      currentSegmentEndPoint.value = trackPoints.value[1];
      currentIndex.value = 0;

      // 让地图视图适配轨迹范围
      map.value.getView().fit(extent, {
        padding: [50, 50, 50, 50],
        duration: 500,
        maxZoom: 16,
      });

      // 等待缩放完成后启动动画
      setTimeout(() => {
        if (isPlaying.value && !isPaused.value) {
          animationFrameId.value = requestAnimationFrame(animateTrack);
        }
      }, 1000);
    });
  };

  const pauseTrack = () => {
    if (!isPlaying.value || isPaused.value) return;
    isPaused.value = true;
    pauseTime.value = performance.now();
    if (animationFrameId.value) {
      cancelAnimationFrame(animationFrameId.value);
      animationFrameId.value = null;
    }
  };

  const resumeTrack = () => {
    if (!isPlaying.value || !isPaused.value) return;
    isPaused.value = false;
    const pauseDuration = performance.now() - pauseTime.value;
    animationStartTime.value += pauseDuration;
    animationFrameId.value = requestAnimationFrame(animateTrack);
  };

  const animateTrack = (currentTime) => {
    if (!isPlaying.value || isPaused.value) return;

    if (animationStartTime.value === 0) {
      animationStartTime.value = currentTime;
    }

    const elapsedTime = (currentTime - animationStartTime.value) / 1000;
    const totalSegments = trackPoints.value.length - 1;

    if (totalSegments <= 0) {
      stopTrack();
      if (resolvePlaybackPromise.value) {
        resolvePlaybackPromise.value();
        resolvePlaybackPromise.value = null;
      }
      return;
    }

    const timePerSegment = segmentDuration.value / 1000;
    const totalDuration = totalSegments * timePerSegment;

    // 播放结束
    if (elapsedTime >= totalDuration) {
      const lastCoord = fromLonLat(trackPoints.value[trackPoints.value.length - 1]);
      if (trackMarker.value) {
        trackMarker.value.getGeometry().setCoordinates(lastCoord);
      }
      // 轨迹线显示完整路径
      if (trackLine.value) {
        const fullCoords = trackPoints.value.map((p) => fromLonLat(p));
        trackLine.value.getGeometry().setCoordinates(fullCoords);
      }
      stopTrack();
      if (resolvePlaybackPromise.value) {
        resolvePlaybackPromise.value();
        resolvePlaybackPromise.value = null;
      }
      return;
    }

    let segmentIndex = Math.min(
      Math.floor(elapsedTime / timePerSegment),
      totalSegments - 1
    );
    const segmentElapsedTime = elapsedTime - segmentIndex * timePerSegment;
    const segmentProgress = Math.min(segmentElapsedTime / timePerSegment, 1);

    if (
      segmentIndex !== currentIndex.value ||
      currentSegmentStartPoint.value === null ||
      currentSegmentEndPoint.value === null
    ) {
      currentIndex.value = segmentIndex;
      currentSegmentStartPoint.value = trackPoints.value[segmentIndex];
      currentSegmentEndPoint.value = trackPoints.value[segmentIndex + 1];
    }

    const startPoint = currentSegmentStartPoint.value;
    const endPoint = currentSegmentEndPoint.value;

    let interpolatedPoint;
    if (segmentProgress >= 1) {
      interpolatedPoint = endPoint;
    } else {
      interpolatedPoint = [
        startPoint[0] + (endPoint[0] - startPoint[0]) * segmentProgress,
        startPoint[1] + (endPoint[1] - startPoint[1]) * segmentProgress,
      ];
    }

    const mercatorCoords = fromLonLat(interpolatedPoint);

    // 更新 marker 位置
    if (trackMarker.value) {
      trackMarker.value.getGeometry().setCoordinates(mercatorCoords);
    }

    // 更新轨迹线：已走过的所有点 + 当前插值位置
    if (trackLine.value) {
      const walkedCoords = [];
      for (let i = 0; i <= segmentIndex; i++) {
        walkedCoords.push(fromLonLat(trackPoints.value[i]));
      }
      walkedCoords.push(mercatorCoords);
      trackLine.value.getGeometry().setCoordinates(walkedCoords);
    }

    animationFrameId.value = requestAnimationFrame(animateTrack);
  };

  const stopTrack = (manualStop = false) => {
    if (animationFrameId.value) {
      cancelAnimationFrame(animationFrameId.value);
      animationFrameId.value = null;
    }

    // 重置状态
    isPlaying.value = false;
    isPaused.value = false;
    pauseTime.value = 0;
    pausePosition.value = 0;
    currentSegmentProgress.value = 0;
    animationStartTime.value = 0;
    currentSegmentStartPoint.value = null;
    currentSegmentEndPoint.value = null;
    currentIndex.value = 0; // 重置索引

    // 只有在不是手动停止且存在解决函数时才解决 Promise
    if (resolvePlaybackPromise.value) {
      if (manualStop) {
        // 如果是手动停止，直接拒绝 Promise 并传递特定消息
        resolvePlaybackPromise.value(Promise.reject("Track playback stopped"));
      } else {
        // 否则正常解决
        resolvePlaybackPromise.value();
      }
      resolvePlaybackPromise.value = null;
    }
  };

  const clearTrack = () => {
    stopTrack();
    if (trackSource.value) {
      trackSource.value.clear();
    }
    if (trackMarker.value) {
      trackMarker.value = null;
    }
    trackLine.value = null;
    currentIndex.value = 0;
    trackPoints.value = [];
  };

  const cleanup = () => {
    // 停止轨迹播放
    stopTrack();
    // 清除业务图层，但保留全局地图实例
    mapStore.resetForNewPage();
    // 重置本地状态引用
    trackMarker.value = null;
    trackLine.value = null;
    trackPoints.value = [];
    isPlaying.value = false;
    isPaused.value = false;
  };

  return {
    map,
    isInitialized,
    initMap,
    addMarker,
    clearMarkers,
    playTrack,
    stopTrack,
    clearTrack,
    cleanup,
    drawLine,
    drawPolygon,
    clearLines,
    clearPolygons,
    clearAllBusinessLayers,
    pauseTrack,
    resumeTrack,
    isPaused,
  };
}
