const COORDINATE_SYSTEMS = new Set(['WGS84', 'GCJ02']);

export function fenceWriteIssue(fence, demoMode = false) {
  if (demoMode) return '';
  if (!COORDINATE_SYSTEMS.has(fence?.coordinateSystem)) return '此围栏使用旧版示意坐标，请新建并在真实地图上重新绘制；历史记录保留。';
  return '';
}
