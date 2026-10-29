import { toMapCoordinates } from './map-coordinates.mjs';

// Current development deployment has one test site. IDs preserve existing
// device ownership and authorization; the display name is not a data migration.
export const TEST_SITE_MODE = true;
export const TEST_SITE = Object.freeze({
  adminId: 'site-1',
  stationId: 'S1',
  name: '测试厂区',
  region: '济南市历下区财政局周边',
  // User-selected landmark: 经十路12111号中润世纪中心3号楼.
  // Fixed surrounding-area center, not a device/user location or a fence.
  // OSM way 664622627 (中润世纪中心), WGS84 centroid via
  // https://mapcarta.com/W664622627; address cross-checked with Jinan's
  // public resource trading office directory. Convert once for the GCJ02 map.
  center: Object.freeze([117.08165, 36.65428]),
  coordinateSystem: 'WGS84',
  zoom: 18,
});

export function testSiteViewport() {
  const center = TEST_SITE.center && toMapCoordinates({ longitude: TEST_SITE.center[0], latitude: TEST_SITE.center[1], coordinateSystem: TEST_SITE.coordinateSystem });
  return center
    ? { center, zoom: TEST_SITE.zoom, configured: true }
    : { center: [105, 35], zoom: 4, configured: false };
}

// Display-only aliases: callers keep original IDs and records for all writes.
export function testSiteName(site, enabled = TEST_SITE_MODE) {
  if (!site) return '';
  return enabled && [TEST_SITE.adminId, TEST_SITE.stationId].includes(site.id) ? TEST_SITE.name : site.name;
}

export function testSiteChoices(sites, kind = 'admin', enabled = TEST_SITE_MODE) {
  const id = kind === 'station' ? TEST_SITE.stationId : TEST_SITE.adminId;
  return (sites || []).filter(site => !enabled || site.id === id).map(site => ({ ...site, name: testSiteName(site, enabled) }));
}
