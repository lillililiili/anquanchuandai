import { formatBeijingDateTime } from './date-time.js';
// The server owns the mode. Unknown configuration must not briefly expose work UI.
export function workBusinessEnabled(db) {
  return db?.state?.businessConfig?.workBusinessEnabled === true;
}

export function workStatus(work) {
  return work?.status === '监护中' ? '进行中' : work?.status || '';
}

export function workPeriod(work) {
  const legacy = (time) => work?.date && time ? `${work.date}T${time.length === 5 ? time + ':00' : time}+08:00` : '';
  return { start: work?.plannedStartAt || legacy(work?.start), end: work?.plannedEndAt || legacy(work?.end) };
}

export function workOnDate(work, date) {
  if (!date) return true;
  const { start, end } = workPeriod(work);
  const from = Date.parse(`${date}T00:00:00+08:00`), to = from + 86400000;
  return Number.isFinite(Date.parse(start)) && Number.isFinite(Date.parse(end))
    ? Date.parse(start) < to && Date.parse(end) > from : work?.date === date;
}

export function currentWorkFor(state, personId, now = Date.now()) {
  if (state?.businessConfig?.workBusinessEnabled !== true) return null;
  const person = state.people?.find(item => item.id === personId && item.active === true);
  if (!person) return null;
  const matches = (state.works || []).filter(work => {
    const { start, end } = workPeriod(work);
    return work.demo !== true && work.dataOrigin !== 'GUARDIAN_SEED' && String(work.source || '').toLowerCase() !== 'demo'
      && workStatus(work) === '进行中' && work.station === person.station && work.members?.includes(personId)
      && work.members.includes(work.leader) && work.members.includes(work.supervisor)
      && Date.parse(start) <= now && now < Date.parse(end)
      && work.members.every(id => state.people?.some(p => p.id === id && p.active === true && p.station === work.station));
  });
  return matches.length === 1 ? matches[0] : null;
}

export const workSource = work => work?.source === 'LOCAL' ? '本地登记' : work?.externalSource || work?.externalSystem || work?.source || '来源未提供';

export function eventSource(event, device) {
  if (event?.source === 'manual_sos') return '手机 SOS';
  if (event?.protocol === 'direct-belt' || device?.source === 'DIRECT_BELT') return '安全带直连';
  if (event?.protocol === 'direct-helmet' || device?.source === 'DIRECT_HELMET') return '安全帽直连';
  return event?.source === 'device' ? '设备上报' : event?.source || '来源未提供';
}

export function clearWorkSelection(session) {
  session.work = '';
  for (const filter of Object.values(session.filters || {})) {
    if (filter && typeof filter === 'object') { delete filter.workId; delete filter.taskId; delete filter.workStatus; }
  }
  if (session.personTab === '作业信息') session.personTab = '人员信息';
  if (session.statsTab === '任务') session.statsTab = '综合';
}

export function withoutWorkQuery(query) {
  const next = { ...query };
  for (const key of ['workId', 'taskId', 'workStatus']) delete next[key];
  if (['任务', '作业', '作业信息', 'works', 'work'].includes(next.tab)) delete next.tab;
  if (next.personTab === '作业信息') delete next.personTab;
  if (next.statsTab === '任务') delete next.statsTab;
  return next;
}

export function workPeriodText(work) {
  const { start, end } = workPeriod(work);
  return `${formatBeijingDateTime(start)} ～ ${formatBeijingDateTime(end)}`;
}
