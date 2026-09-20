// Separated, deterministic sample work areas. Never used by real device providers.
export function sampleWorkArea(site, index) {
  const column = (index - 1) % 5, row = Math.floor((index - 1) / 5)
  const round = value => Number(value.toFixed(6))
  const longitude = round(116.25 + (site - 1) * 0.18 + column * 0.014 + (row % 2) * 0.003 + Math.sin(index * 2.4) * 0.0015)
  const latitude = round(39.86 + (site - 1) * 0.09 + row * 0.01 + Math.cos(index * 1.7) * 0.0015)
  const width = 0.0012 + (index % 3) * 0.0003, height = 0.0008 + (index % 4) * 0.00015
  const ring = [[-width, -height], [width, -height], [width, height], [-width, height], [-width, -height]]
    .map(([x, y]) => [round(longitude + x), round(latitude + y)])
  return { longitude, latitude, ring }
}
