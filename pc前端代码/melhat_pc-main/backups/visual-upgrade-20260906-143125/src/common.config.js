// export const satelliteTilesUrl =
//   import.meta.env.VITE_APP_MAP_TILES_URL + '/tiles/satellite/{z}/{x}/{y}.jpg';
// export const overlayTilesUrl =
//   import.meta.env.VITE_APP_MAP_TILES_URL + '/tiles/overlay/{z}/{x}/{y}.jpg';

export const satelliteTilesUrl =
  'https://webst01.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}'

export const overlayTilesUrl =
  'https://webst01.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}'

export const centerPoint = [117.14473200, 36.66388700];
export const zoom = 15; // 初始缩放级别
export const minZoom = 3; // 最小缩放级别
export const maxZoom = 18; // 最大缩放级别

export const BIG_SCREEN_BG = import.meta.env.VITE_APP_BIG_SCREEN_BG_URL;
export const WEB_SOCKET_URL = import.meta.env.VITE_APP_SOCKET_URL;

// tag颜色列表
export const exigencyColors = {
  1: '#FF0000', // 紧急
  2: '#FFA500', // 重要
  3: '#e7d223', // 一般
};

export const taskColors = {
  0: '#0000FF', // 待分发
  1: '#FFA500', // 待执行
  2: '#800080', // 待审核
  3: '#17e817', // 执行中
  4: '#949410', // 待确认
  5: '#FF0000', // 待验收
  6: '#6CBAD3', // 已完成
  7: '#00FFFF', // 组内审批
  8: '#FF00FF', // 场站审批
  9: '#A52A2A', // 公司审批
  10: '#008000', // 已完成
};

export const approveColors = {
  0: '#800080', // 待审批
  1: '#17e817', // 审批中
  2: '#FF0000', // 审批不通过
  3: '#008000', // 审批通过
};
