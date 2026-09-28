// 阳城电厂（大唐阳城电厂）临时中心。页面仍保存 0–100 的示意坐标，这里只负责投影。
export const PLANT_CENTER = [112.574204, 35.466123];
export const PLANT_ZOOM = 16;
export const MIN_ZOOM = 3;
export const MAX_ZOOM = 18;

export const SATELLITE_TILES =
  "https://webst01.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}";
export const LABEL_TILES =
  "https://webst01.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}";

// 覆盖电厂附近约 1.6km × 1.2km，使初始 16 级能看到整片示意区域。
const HALF_LON = 0.009;
const HALF_LAT = 0.0055;

export function percentToLonLat(point) {
  const x = Number(point[0]);
  const y = Number(point[1]);
  return [
    PLANT_CENTER[0] - HALF_LON + (x / 100) * HALF_LON * 2,
    PLANT_CENTER[1] + HALF_LAT - (y / 100) * HALF_LAT * 2,
  ];
}

export function lonLatToPercent(lonLat) {
  return [
    ((lonLat[0] - (PLANT_CENTER[0] - HALF_LON)) / (HALF_LON * 2)) * 100,
    ((PLANT_CENTER[1] + HALF_LAT - lonLat[1]) / (HALF_LAT * 2)) * 100,
  ];
}

export function clampPercent(point) {
  return [
    Math.max(0, Math.min(100, point[0])),
    Math.max(0, Math.min(100, point[1])),
  ];
}
