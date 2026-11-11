export const isGeofenceAlarm = event => event?.source === 'PLATFORM_GEOFENCE' && event?.type === '电子围栏';

// Only compare successful, authorized snapshots. Existing history establishes the
// baseline; it must not flood the page on login or when switching sites.
export function createGeofenceNoticeTracker() {
  let scope = '', initialized = false;
  const seen = new Set(), pending = new Map();
  const items = () => [...pending.values()].reverse();
  function reset() { scope = ''; initialized = false; seen.clear(); pending.clear(); }
  return {
    reset,
    dismiss(id) { pending.delete(id); return items(); },
    dismissAll() { pending.clear(); return []; },
    update({ accountId, station, online, events = [] }) {
      if (!accountId || !station) { reset(); return []; }
      const nextScope = JSON.stringify([accountId, station]);
      if (scope !== nextScope) { reset(); scope = nextScope; }
      if (!online) return items();
      const authorized = events.filter(item => item.station === station && isGeofenceAlarm(item) && item.id);
      const current = new Map(authorized.map(item => [item.id, item]));
      for (const id of pending.keys()) {
        const item = current.get(id);
        if (!item || item.status === '已核验') pending.delete(id);
        else pending.set(id, item);
      }
      for (const item of [...authorized].sort((a, b) => String(a.occurredAt || a.createdAt || '').localeCompare(String(b.occurredAt || b.createdAt || '')))) {
        if (initialized && !seen.has(item.id) && item.status !== '已核验') pending.set(item.id, item);
        seen.add(item.id);
      }
      initialized = true;
      return items();
    },
  };
}
