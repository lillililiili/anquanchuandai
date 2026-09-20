// Simple WGS84 rings only: no holes, touching edges, crossings or degenerate polygons.
export function normalizeRing(input) {
  if (!Array.isArray(input) || input.length > 501) throw new Error('围栏最多500个节点')
  const points = input.map(p => {
    if (!Array.isArray(p) || p.length !== 2 || !p.every(Number.isFinite) || Math.abs(p[0]) > 180 || Math.abs(p[1]) > 85.0511287798) throw new Error('节点必须是有效WGS84经纬度')
    return [...p]
  })
  const same = (a, b) => a[0] === b[0] && a[1] === b[1]
  if (points.length > 1 && same(points[0], points.at(-1))) points.pop()
  if (points.length < 3 || new Set(points.map(p => p.join(','))).size !== points.length) throw new Error('至少三个不同顶点，不能包含重复节点')
  const cross = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
  const on = (a, b, p) => Math.abs(cross(a, b, p)) < 1e-12 && p[0] >= Math.min(a[0], b[0]) && p[0] <= Math.max(a[0], b[0]) && p[1] >= Math.min(a[1], b[1]) && p[1] <= Math.max(a[1], b[1])
  const intersects = (a, b, c, d) => cross(a, b, c) * cross(a, b, d) < 0 && cross(c, d, a) * cross(c, d, b) < 0 || on(a, b, c) || on(a, b, d) || on(c, d, a) || on(c, d, b)
  for (let i = 0; i < points.length; i++) {
    const a = points[i], b = points[(i + 1) % points.length], next = points[(i + 2) % points.length]
    if (Math.abs(cross(a, b, next)) < 1e-12) throw new Error('相邻节点不能重叠或共线折返')
    for (let j = i + 2; j < points.length; j++) {
      if (i === 0 && j === points.length - 1) continue
      if (intersects(a, b, points[j], points[(j + 1) % points.length])) throw new Error('围栏不能自相交或边界相触')
    }
  }
  const origin = points[0]
  const area = points.reduce((sum, p, i) => sum + cross(origin, p, points[(i + 1) % points.length]), 0)
  if (Math.abs(area) < 1e-12) throw new Error('围栏面积不能为零')
  return [...points, [...points[0]]]
}
