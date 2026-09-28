export const PLANT_CENTER = [112.574204, 35.466123];
export const PLANT_ZOOM = 16;
export const SATELLITE_TILES = "https://webst01.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}";
export const LABEL_TILES = "https://webst01.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}";
const HALF_LON = 0.009;
const HALF_LAT = 0.0055;

export function percentToLonLat(point) {
  return [
    PLANT_CENTER[0] - HALF_LON + (Number(point[0]) / 100) * HALF_LON * 2,
    PLANT_CENTER[1] + HALF_LAT - (Number(point[1]) / 100) * HALF_LAT * 2,
  ];
}

export function lonLatToPercent(lonLat) {
  return [
    Math.max(0, Math.min(100, ((lonLat[0] - (PLANT_CENTER[0] - HALF_LON)) / (HALF_LON * 2)) * 100)),
    Math.max(0, Math.min(100, ((PLANT_CENTER[1] + HALF_LAT - lonLat[1]) / (HALF_LAT * 2)) * 100)),
  ];
}
