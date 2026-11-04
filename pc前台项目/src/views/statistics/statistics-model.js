import { workBusinessEnabled, workOnDate } from '../../lib/work-business.js';
// Current equipment is not a historical observation. Dates select recorded
// works/events only; never infer past ownership or online rates from today's state.
export function statisticsView(db, scope = {}) {
  if (!workBusinessEnabled(db)) scope = { ...scope, workId: "" };
  const current = db.stats({ ...scope, date: '' });
  const recorded = db.stats(scope);
  const onDate = row => !scope.date || row.date === scope.date;
  const works = workBusinessEnabled(db) ? recorded.works.filter(work => workOnDate(work, scope.date)) : [], events = recorded.events.filter(onDate);
  return {
    ...current, works, events,
    unresolved: events.filter(event => event.status !== '已核验').length,
    verified: events.filter(event => event.status === '已核验').length,
  };
}

export function personRealEquipmentCount(db, stats, personId) {
  return stats.devices.filter(device => db.owner(device.id)?.id === personId).length;
}
