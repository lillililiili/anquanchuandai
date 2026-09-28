// Shared by the portal and the screen: areas and positions use the same 0–100 coordinates.
const legacyAreas = [
  { id: "area-boiler", name: "锅炉区", points: [[29, 20], [43, 20], [43, 58], [29, 58]] },
  { id: "area-electric", name: "配电区", points: [[13, 61], [29, 61], [29, 87], [13, 87]] },
  { id: "area-turbine", name: "汽机厂房", points: [[40, 64], [65, 64], [65, 83], [40, 83]] },
  { id: "area-water", name: "循环水区", points: [[73, 27], [90, 27], [90, 75], [73, 75]] },
];

export function validPosition(point) {
  return Array.isArray(point) && point.length === 2 && point.every((value) => Number.isFinite(value) && value >= 0 && value <= 100);
}

function validArea(area) {
  if (!Array.isArray(area.points) || area.points.length < 3 || !area.points.every(validPosition)) return false;
  return Math.abs(area.points.reduce((sum, p, i, points) => {
    const q = points[(i + 1) % points.length];
    return sum + p[0] * q[1] - q[0] * p[1];
  }, 0)) > 1e-8;
}

export function displayedAreas(state, station) {
  // An explicit empty list means no configured areas; never restore demo areas for it.
  const source = Array.isArray(state.mapAreas)
    ? state.mapAreas
    : station === state.stations?.[0]?.id ? legacyAreas.map((area) => ({ ...area, station })) : [];
  return source.filter((area) => area.station === station && area.enabled !== false && !area.archived && validArea(area));
}

export function pointInArea(point, points) {
  if (!validPosition(point)) return false;
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const [x1, y1] = points[j], [x2, y2] = points[i];
    const [x, y] = point;
    const cross = (x - x1) * (y2 - y1) - (y - y1) * (x2 - x1);
    // Include boundary points, including vertices, consistently on every edge.
    if (Math.abs(cross) < 1e-8 && x >= Math.min(x1, x2) - 1e-8 && x <= Math.max(x1, x2) + 1e-8 && y >= Math.min(y1, y2) - 1e-8 && y <= Math.max(y1, y2) + 1e-8) return true;
    if ((y1 > y) !== (y2 > y) && x < ((x2 - x1) * (y - y1)) / (y2 - y1) + x1) inside = !inside;
  }
  return inside;
}

export function areaOccupancy(state, station, isLocationValid) {
  const areas = displayedAreas(state, station).map((area) => ({ ...area, personIds: [] }));
  const people = [...new Map(state.people.filter((person) => person.station === station && person.active).map((person) => [person.id, person])).values()];
  let inside = 0, outside = 0, unverified = 0, overlapping = 0;
  for (const person of people) {
    if (!validPosition(person.position) || !isLocationValid(person.id)) {
      unverified++;
      continue;
    }
    const matches = areas.filter((area) => pointInArea(person.position, area.points));
    matches.forEach((area) => area.personIds.push(person.id));
    if (matches.length) inside++;
    else outside++;
    if (matches.length > 1) overlapping++;
  }
  return { areas, total: people.length, inside, outside, unverified, overlapping };
}
