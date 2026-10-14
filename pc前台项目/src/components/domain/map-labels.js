// Positions use OpenLayers viewport pixels, before the dashboard's CSS scaling.
export function placeAreaLabel({ center, bounds, size, viewport, occupied, contains }) {
  const [width, height] = size;
  const [left, top, right, bottom] = bounds;
  const candidates = [center];
  for (let row = 0; row <= 6; row++) {
    for (let column = 0; column <= 4; column++) {
      candidates.push([left + (right - left) * column / 4, top + (bottom - top) * row / 6]);
    }
  }
  // Small regions can be too crowded for a label; keep it next to their outline.
  candidates.push([center[0], top - height / 2 - 8], [center[0], bottom + height / 2 + 8]);
  let best = center, bestScore = Infinity;
  for (const point of candidates) {
    const box = [point[0] - width / 2 - 4, point[1] - height / 2 - 4, point[0] + width / 2 + 4, point[1] + height / 2 + 4];
    if (box[0] < 4 || box[1] < 4 || box[2] > viewport[0] - 4 || box[3] > viewport[1] - 4) continue;
    const collisions = occupied.filter(other => box[0] < other[2] && box[2] > other[0] && box[1] < other[3] && box[3] > other[1]).length;
    const inside = [[box[0], box[1]], [box[2], box[1]], [box[2], box[3]], [box[0], box[3]]].every(contains);
    const score = collisions * 1e6 + (inside ? 0 : 1e4) + Math.hypot(point[0] - center[0], point[1] - center[1]);
    if (score < bestScore) { best = point; bestScore = score; }
  }
  return best;
}
