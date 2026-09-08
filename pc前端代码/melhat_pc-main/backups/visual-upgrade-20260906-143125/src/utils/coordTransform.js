/**
 * 坐标转换工具
 *
 * 中国地图坐标系说明：
 * - WGS84: 国际标准坐标系（GPS原始坐标）
 * - GCJ-02: 火星坐标系（国测局标准，高德、腾讯等中国地图服务商使用）
 *
 * 本工具提供 GCJ-02 与 WGS84 之间的相互转换
 */

const PI = 3.141592653589793;
const A = 6378245.0;
const EE = 0.006693421622965943;

/**
 * 判断坐标是否在中国境内
 */
function isInChina(lng, lat) {
  return lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271;
}

/**
 * 转换纬度偏移量
 */
function transformLat(x, y) {
  let ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
  ret += (20.0 * Math.sin(6.0 * x * PI) + 20.0 * Math.sin(2.0 * x * PI)) * 2.0 / 3.0;
  ret += (20.0 * Math.sin(y * PI) + 40.0 * Math.sin(y / 3.0 * PI)) * 2.0 / 3.0;
  ret += (160.0 * Math.sin(y / 12.0 * PI) + 320 * Math.sin(y * PI / 30.0)) * 2.0 / 3.0;
  return ret;
}

/**
 * 转换经度偏移量
 */
function transformLng(x, y) {
  let ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
  ret += (20.0 * Math.sin(6.0 * x * PI) + 20.0 * Math.sin(2.0 * x * PI)) * 2.0 / 3.0;
  ret += (20.0 * Math.sin(x * PI) + 40.0 * Math.sin(x / 3.0 * PI)) * 2.0 / 3.0;
  ret += (150.0 * Math.sin(x / 12.0 * PI) + 300.0 * Math.sin(x / 30.0 * PI)) * 2.0 / 3.0;
  return ret;
}

/**
 * 计算坐标偏移量（共享逻辑）
 */
function getDelta(lng, lat) {
  const dLat = transformLat(lng - 105.0, lat - 35.0);
  const dLng = transformLng(lng - 105.0, lat - 35.0);
  const radLat = lat / 180.0 * PI;
  const magic = 1 - EE * Math.sin(radLat) * Math.sin(radLat);
  const sqrtMagic = Math.sqrt(magic);

  return {
    dLat: (dLat * 180.0) / ((A * (1 - EE)) / (magic * sqrtMagic) * PI),
    dLng: (dLng * 180.0) / (A / sqrtMagic * Math.cos(radLat) * PI)
  };
}

/**
 * WGS84 转 GCJ-02（火星坐标系）
 * 用于将GPS原始坐标转换为在中国地图上显示的坐标
 *
 * @param {number} lng - WGS84经度
 * @param {number} lat - WGS84纬度
 * @returns {[number, number]} - GCJ-02坐标 [经度, 纬度]
 */
export function wgs84ToGcj02(lng, lat) {
  if (!isInChina(lng, lat)) {
    return [lng, lat];
  }

  const { dLat, dLng } = getDelta(lng, lat);
  return [lng + dLng, lat + dLat];
}

/**
 * GCJ-02（火星坐标系）转 WGS84
 * 用于将中国地图上的坐标转换为GPS原始坐标（保存到数据库时使用）
 *
 * @param {number} lng - GCJ-02经度
 * @param {number} lat - GCJ-02纬度
 * @returns {[number, number]} - WGS84坐标 [经度, 纬度]
 */
export function gcj02ToWgs84(lng, lat) {
  if (!isInChina(lng, lat)) {
    return [lng, lat];
  }

  const { dLat, dLng } = getDelta(lng, lat);
  return [lng - dLng, lat - dLat];
}

/**
 * 批量转换坐标数组（GCJ-02 转 WGS84）
 *
 * @param {Array<Array<number>>} coords - GCJ-02坐标数组
 * @returns {Array<Array<number>>} - WGS84坐标数组
 */
export function gcj02ToWgs84Batch(coords) {
  return coords.map(([lng, lat]) => gcj02ToWgs84(lng, lat));
}

/**
 * 批量转换坐标数组（WGS84 转 GCJ-02）
 *
 * @param {Array<Array<number>>} coords - WGS84坐标数组
 * @returns {Array<Array<number>>} - GCJ-02坐标数组
 */
export function wgs84ToGcj02Batch(coords) {
  return coords.map(([lng, lat]) => wgs84ToGcj02(lng, lat));
}